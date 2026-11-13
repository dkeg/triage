import AppKit
import SwiftUI
import TriageCore

@MainActor
final class IslandController {
    static let shared = IslandController()

    let model = IslandModel()
    private var panel: IslandPanel?
    private var hosting: IslandHostingView<IslandView>?
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var openedByAttention = false
    private(set) var isVisible = true
    private var server: HookServer?
    private let focuser = SessionFocuser()
    private(set) lazy var probe = SystemIslandProbe(model: model)
    private var pillWidthMode: PillWidthMode {
        PillWidthMode(rawValue: defaults.string(forKey: Pref.pillWidth) ?? "") ?? .wide
    }

    private var defaults: UserDefaults { .standard }
    private var hoverOpen: Bool { defaults.object(forKey: Pref.hoverOpen) as? Bool ?? true }
    private var hoverDelay: Double { defaults.object(forKey: Pref.hoverDelay) as? Double ?? 0.25 }
    private var autoOpen: Bool { defaults.object(forKey: Pref.autoOpenOnAttention) as? Bool ?? true }
    private var holdWhenFocused: Bool { defaults.object(forKey: Pref.holdWhenFocused) as? Bool ?? true }
    private var autoCollapse: Double { defaults.object(forKey: Pref.autoCollapseSeconds) as? Double ?? 12 }

    func start() {
        let panel = IslandPanel()
        let host = IslandHostingView(rootView: IslandView(model: model, onResolve: { [weak self] approve in
            self?.resolve(approve: approve)
        }, onJump: { [weak self] session in
            self?.jump(to: session)
        }))
        host.sizingOptions = []
        host.activeRect = { [weak self] in
            MainActor.assumeIsolated { self?.hitRect ?? .zero }
        }
        panel.contentView = host
        self.panel = panel
        self.hosting = host
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        startServer()
        applyPillWidthMode()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPillWidthMode() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, self.model.revealDeferred(frontmostBundleID: app?.bundleIdentifier) else { return }
                self.attentionArrived()
            }
        }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        if let c = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.mode != .collapsed else { return }
                self.openedByAttention = false
                self.set(.collapsed)
            }
        }) { monitors.append(c) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) {
            monitors.append(l)
        }
    }

    /// Applies the width setting and runs the system-island probe only in Auto.
    func applyPillWidthMode() {
        let mode = pillWidthMode
        guard mode != model.pillWidthMode || (mode == .auto) != (probe.status != .idle) else { return }
        model.pillWidthMode = mode
        if mode == .auto { probe.start() } else { probe.stop() }
    }

    // MARK: Hook server

    private func startServer() {
        let server = HookServer { data, conn in
            Task { @MainActor in IslandController.shared.handleHook(data, conn) }
        }
        do { try server.start(); self.server = server }
        catch { NSLog("Triage: hook server failed to start: \(error.localizedDescription)") }
    }

    func handleHook(_ data: Data, _ conn: HookConnection) {
        guard let event = HookEvent.decode(data) else { conn.reply(Data()); return }
        if event.eventName == "PermissionRequest" {
            let host = focuser.hostApp(for: event.triage)
            let hostID = host?.bundleIdentifier
            let hold = holdWhenFocused && hostID != nil
                && hostID == NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            TriageLog.write("PermissionRequest session=\(event.sessionID ?? "?") tool=\(event.toolName ?? "?") host=\(hostID ?? "none") frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") hold=\(hold)")
            let id = model.addPermission(event, hostBundleID: hostID, hostName: host?.localizedName, deferred: hold) { approve in
                TriageLog.write("decision approve=\(approve) session=\(event.sessionID ?? "?")")
                conn.reply(HookDecision.permissionResponse(allow: approve,
                                                           message: approve ? nil : "Denied from Triage"))
            }
            guard let id else { conn.reply(Data()); return }
            conn.setOnClose { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    TriageLog.write("peer closed (answered elsewhere or hook killed) session=\(event.sessionID ?? "?")")
                    self.model.cancelPermission(id)
                    if self.model.pending.isEmpty, self.openedByAttention { self.scheduleCollapse(after: 0.6) }
                }
            }
            if !hold { attentionArrived() }
        } else {
            TriageLog.write("\(event.eventName) session=\(event.sessionID ?? "?")")
            model.apply(event)
            conn.reply(Data())
        }
    }

    func reposition() {
        guard let panel, let screen = IslandGeometry.preferredScreen() else { return }
        model.geometry = .compute(for: screen)
        panel.setFrame(model.geometry.panelFrame, display: true)
    }

    func toggleVisibility() {
        isVisible.toggle()
        isVisible ? panel?.orderFrontRegardless() : panel?.orderOut(nil)
    }

    // MARK: Mode changes

    func set(_ mode: IslandMode) {
        guard model.mode != mode else { return }
        model.mode = mode
    }

    /// Called after the user approves/denies from the island.
    func resolve(approve: Bool) {
        model.resolve(approve: approve)
        openedByAttention = false
        scheduleCollapse(after: 0.6)
    }

    /// Brings the session's terminal forward and tucks the island away.
    func jump(to session: Session) {
        focuser.focus(session)
        openedByAttention = false
        scheduleCollapse(after: 0.15)
    }

    func simulateAttention() {
        model.simulateAttention()
        attentionArrived()
    }

    func attentionArrived() {
        guard autoOpen else { return }
        openedByAttention = true
        collapseTask?.cancel()
        set(.expanded)
        scheduleCollapse(after: autoCollapse)
    }

    private func scheduleCollapse(after seconds: Double) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if self.model.attention == nil || self.openedByAttention {
                self.openedByAttention = false
                self.set(.collapsed)
            }
        }
    }

    // MARK: Hover

    /// Shape rect in global screen coordinates for the current mode.
    private var currentRect: CGRect {
        let g = model.geometry
        let s = model.size
        let top = g.screenFrame.maxY - IslandModel.topInset
        return CGRect(x: g.cutout.midX - s.width / 2, y: top - s.height, width: s.width, height: s.height)
    }

    /// Pill rect in the panel's content-view coordinates, used for click-through hit testing.
    private var hitRect: CGRect {
        guard let panel, model.size != .zero else { return .zero }
        let r = currentRect, f = panel.frame
        return CGRect(x: r.minX - f.minX, y: r.minY - f.minY, width: r.width, height: r.height)
    }

    private func mouseMoved() {
        guard isVisible else { return }
        let inside = model.size != .zero && currentRect.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
        if inside {
            collapseTask?.cancel()
            guard hoverOpen, model.mode == .collapsed, hoverTask == nil else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.hoverDelay ?? 0.25))
                guard !Task.isCancelled, let self else { return }
                self.hoverTask = nil
                self.openedByAttention = false
                self.set(.expanded)
            }
        } else {
            hoverTask?.cancel(); hoverTask = nil
            if model.mode != .collapsed {
                let pending = openedByAttention && model.attention != nil
                scheduleCollapse(after: pending ? autoCollapse : 0.3)
            }
        }
    }
}
