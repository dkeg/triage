import AppKit
import ScreenCaptureKit

/// Pure measurement of the system island's width from a capture of the top-center strip
/// (triage's own windows excluded).
///
/// The island is pure black, so instead of looking for a bright wallpaper edge (which fails on
/// dark wallpapers) this finds the outermost black pixel on each side. Things drawn inside the
/// island (album art, a waveform, a timer) are narrower than `gapPoints`, so they don't end the run.
enum SystemIslandMeasure {
    /// Vertical extent of the island in points from the top of the screen (used to correct for its
    /// rounded ends on the rows that are sampled).
    static let top: CGFloat = 4, bottom: CGFloat = 42
    /// A pixel at or below this luminance is "island black".
    static let blackLevel: CGFloat = 0.006
    /// Contents wider than this end the island (wallpaper), narrower ones are Live Activity art/text.
    static let gapPoints: CGFloat = 40
    /// Rows sampled, in points from the top: the middle band, where the ends are nearly square.
    static let rows: [CGFloat] = [14, 20, 26, 32]

    /// - Returns: island width in points, or nil when no edge can be found (for example a
    ///   completely black wallpaper), so callers should keep their last good value.
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
        let gap = Int(gapPoints * scale)
        let cx = w / 2

        /// Distance (px) from the center to the island's edge on one side, or nil if the row never
        /// leaves the island (it all looks black) or the center isn't black at all.
        func extent(_ y: Int, dir: Int) -> Int? {
            guard lum(cx, y) <= blackLevel else { return nil }
            var lastBlack = 0
            var d = 0
            while true {
                let x = cx + dir * d
                if x < 0 || x >= w { return nil }                 // ran off the strip: never found the edge
                if lum(x, y) <= blackLevel { lastBlack = d } else if d - lastBlack > gap { return lastBlack }
                d += 1
            }
        }

        let r = (bottom - top) / 2
        var best: CGFloat?
        for yPt in rows {
            let y = min(max(Int(yPt * scale), 0), h - 1)
            guard let l = extent(y, dir: -1), let rr = extent(y, dir: 1) else { continue }
            // Add back what the rounded ends take off at this row.
            let d = min(yPt - top, bottom - yPt)
            let dy = max(r - d, 0)
            let comp = 2 * (r - (r * r - dy * dy).squareRoot())
            let width = CGFloat(l + rr + 1) / scale + comp
            best = max(best ?? 0, width)
        }
        return best
    }
}

extension SystemIslandMeasure {
    /// Counts strong horizontal edges (menu bar icon and text strokes) inside `region`, given in
    /// points from the top-left of the strip. A plain wallpaper has few; icons have many.
    static func iconEdgeCount(in image: CGImage, scale: CGFloat, region: CGRect) -> Int {
        let w = image.width, h = image.height
        guard w > 8, h > 8 else { return 0 }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func lum(_ x: Int, _ y: Int) -> CGFloat {
            let i = (y * w + x) * 4
            return (0.2126 * CGFloat(buf[i]) + 0.7152 * CGFloat(buf[i + 1]) + 0.0722 * CGFloat(buf[i + 2])) / 255
        }
        let x0 = max(Int(region.minX * scale), 0), x1 = min(Int(region.maxX * scale), w - 3)
        let y0 = max(Int(region.minY * scale), 0), y1 = min(Int(region.maxY * scale), h - 1)
        guard x0 < x1, y0 < y1 else { return 0 }
        let step = max(Int(scale), 1)                     // compare pixels one point apart
        var count = 0
        for y in stride(from: y0, to: y1, by: 2) {
            for x in x0..<x1 where abs(lum(x + step, y) - lum(x, y)) > edgeContrast { count += 1 }
        }
        return count
    }

    /// Minimum luminance jump between neighbouring points to count as an icon edge.
    static let edgeContrast: CGFloat = 0.30
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
                try? await Task.sleep(for: .milliseconds(Self.hasPermission ? 250 : 2000))
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        model.measuredIslandWidth = nil
        model.yielding = false
        model.menuIconsOverlap = false
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
            // Unreadable frames (nil) keep the last good value instead of snapping to a fallback.
            model.ingestIslandReading(measured)
            // Step aside when menu bar icons sit where the pill would be (e.g. revealed by a menu-bar manager).
            if UserDefaults.standard.object(forKey: Pref.avoidMenuIcons) as? Bool ?? true {
                let region = model.pillRectInStrip(stripWidth: regionW)
                model.ingestIconEdges(SystemIslandMeasure.iconEdgeCount(in: img, scale: scale, region: region))
            } else {
                model.menuIconsOverlap = false
            }
            if status != .running { status = .running }
        } catch {
            if !Self.hasPermission { status = .needsPermission; model.measuredIslandWidth = nil }
            else { status = .failed(error.localizedDescription) }
        }
    }
}
