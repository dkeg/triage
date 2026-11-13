import AppKit
import ScreenCaptureKit

/// Pure measurement of the system island's width from a capture of the top-center strip
/// (our own windows excluded). Kept separate from capture so it can be unit tested.
enum SystemIslandMeasure {
    /// Vertical extent of the island in points, measured from the top of the screen.
    static let top: CGFloat = 4, bottom: CGFloat = 42

    /// - Parameters:
    ///   - image: capture whose horizontal center is the island's center, `scale` px per pt.
    /// - Returns: island width in points, or nil if no edge was found (e.g. a dark wallpaper).
    static func width(in image: CGImage, scale: CGFloat) -> CGFloat? {
        let w = image.width, h = image.height
        guard w > 8, h > 8 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func lum(_ x: Int, _ y: Int) -> CGFloat {
            let i = (y * w + x) * 4
            return (0.2126 * CGFloat(buf[i]) + 0.7152 * CGFloat(buf[i + 1]) + 0.0722 * CGFloat(buf[i + 2])) / 255
        }
        /// Distance from the center to the first sustained bright run, scanning outward.
        func edge(_ y: Int, dir: Int) -> Int? {
            let cx = w / 2
            var run = 0
            for d in 0..<(w / 2 - 1) {
                let x = cx + dir * d
                if lum(x, y) > 0.2 { run += 1; if run >= 3 { return d - 2 } } else { run = 0 }
            }
            return nil
        }
        // Rows near the top and bottom of the pill avoid the artwork/glyphs in the middle.
        // The ends are rounded there, so add back the chord the curve removes.
        let r = (bottom - top) / 2
        func measure(yPt: CGFloat) -> CGFloat? {
            let y = min(max(Int(yPt * scale), 0), h - 1)
            guard let l = edge(y, dir: -1), let rr = edge(y, dir: 1) else { return nil }
            let fromTopOrBottom = min(yPt - top, bottom - yPt)
            let dy = max(r - fromTopOrBottom, 0)
            let comp = 2 * (r - (r * r - dy * dy).squareRoot())
            return CGFloat(max(l, rr)) * 2 / scale + comp
        }
        let samples = [measure(yPt: 9), measure(yPt: 36)].compactMap { $0 }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / CGFloat(samples.count)
    }
}

/// Watches the system island's width so the collapsed pill can widen only when the system
/// island does. Needs Screen Recording permission; nothing is stored or sent anywhere.
@MainActor
final class SystemIslandProbe {
    enum Status: Equatable { case idle, needsPermission, running, failed(String) }
    private(set) var status: Status = .idle { didSet { onStatus?(status) } }
    var onStatus: ((Status) -> Void)?
    private var task: Task<Void, Never>?
    private var lastLogged: CGFloat?
    private unowned let model: IslandModel

    init(model: IslandModel) { self.model = model }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks for Screen Recording. On current macOS the system prompt (and the entry in
    /// Privacy & Security > Screen Recording) only appears once the app actually tries to capture,
    /// so the old CGRequestScreenCaptureAccess call alone isn't enough.
    @MainActor
    static func registerForAccess(activate: Bool = false) {
        // Only come forward when the user asked (the Grant button), never at launch.
        if activate { NSApp.activate(ignoringOtherApps: true) }
        let granted = CGRequestScreenCaptureAccess()
        TriageLog.write("screen recording: CGRequestScreenCaptureAccess -> \(granted)")
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                TriageLog.write("screen recording: capture attempt ok (\(content.displays.count) displays)")
            } catch {
                let e = error as NSError
                TriageLog.write("screen recording: capture attempt failed domain=\(e.domain) code=\(e.code) \(e.localizedDescription)")
            }
        }
    }

    func start() {
        guard task == nil else { return }
        if !Self.hasPermission {
            status = .needsPermission
            // Ask once on our own; after that only the Grant button asks again, so a refusal
            // (or a prompt that was missed) isn't repeated on every launch.
            let key = "screenAccessRequested"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                Self.registerForAccess()
            }
            TriageLog.write("probe: waiting for Screen Recording permission")
        }
        task = Task { [weak self] in
            // Keep checking until permission is granted, then sample continuously.
            while !Task.isCancelled {
                if Self.hasPermission { await self?.sample() }
                else { await MainActor.run { self?.status = .needsPermission } }
                try? await Task.sleep(for: .milliseconds(Self.hasPermission ? 500 : 2000))
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        model.measuredIslandWidth = nil
        model.yielding = false
        status = .idle
    }

    private func sample() async {
        let g = model.geometry
        guard g.screenFrame.width > 0, let screen = IslandGeometry.preferredScreen(),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }
        let scale = screen.backingScaleFactor
        let regionW: CGFloat = 600, regionH: CGFloat = 48
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            let mine = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = CGRect(x: g.cutout.midX - g.screenFrame.minX - regionW / 2, y: 0,
                                    width: regionW, height: regionH)
            cfg.width = Int(regionW * scale); cfg.height = Int(regionH * scale)
            cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let measured = SystemIslandMeasure.width(in: img, scale: scale)
            if measured.map({ Int($0 / 4) }) != lastLogged.map({ Int($0 / 4) }) || (measured == nil) != (lastLogged == nil) {
                TriageLog.write("probe: system island width = \(measured.map { String(format: "%.0f", $0) } ?? "unknown")pt")
                lastLogged = measured
            }
            model.measuredIslandWidth = measured
            // Spotlight / Siri open the island wide; get out of the way until it closes again.
            model.yielding = (measured ?? 0) > 420
            if status != .running { status = .running }
        } catch {
            if !Self.hasPermission { status = .needsPermission; model.measuredIslandWidth = nil }
            else { status = .failed(error.localizedDescription) }
        }
    }
}
