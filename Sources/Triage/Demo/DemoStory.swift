import AppKit
import Observation
import SwiftUI
import TriageCore

/// A scripted, repeatable demo used to record the website animations (`--demo-story`).
///
/// Scenes (`--demo-scene=NAME`): `approval` (default: the full request/approve story), `pill` (the
/// collapsed pill alone, including the red "pending" flash) and `music` (a Live Activity opens in the
/// island and the pill slides aside; the Live Activity is drawn by the stage, so no real music or
/// album art is shown).
///
/// It replaces everything real (sessions, terminals, the hook server) with fake data, puts the
/// island on a plain dark "stage" window with the menu bar hidden, and plays a short approval
/// story. A separate tool (scripts/demo/demo-cursor.swift) moves the real pointer, so the click on
/// Approve goes through the normal code path.
@MainActor
final class DemoStory {
    static var isEnabled: Bool { CommandLine.arguments.contains("--demo-story") }

    static var scene: String {
        CommandLine.arguments.first { $0.hasPrefix("--demo-scene=") }.map { String($0.dropFirst("--demo-scene=".count)) } ?? "approval"
    }

    /// Preferences for this process only (the argument domain outranks stored values and writes nothing).
    static func installOverrides() {
        UserDefaults.standard.setVolatileDomain([
            Pref.autoCollapseSeconds: 6.0, Pref.hoverDelay: 0.35, Pref.pillNudge: 0.0,
            Pref.rowsPerSection: 4, Pref.cardLayout: CardLayout.sideBySide.rawValue,
            Pref.rotateSeconds: 2.2, Pref.pillSide: PillSide.left.rawValue,
            Pref.holdWhenFocused: false, Pref.showTerminals: true, Pref.avoidMenuIcons: false,
            Pref.approvalTimeout: 600.0,
            // The strip scenes show the pill only, so a request must not open the card.
            Pref.autoOpenOnAttention: scene == "approval",
        ], forName: UserDefaults.argumentDomain)
    }

    private unowned let controller: IslandController
    private var model: IslandModel { controller.model }
    private var stage: NSWindow?
    private var t0 = Date()
    private let island = DemoIsland()
    private let marker = DemoMarker()

    init(controller: IslandController) { self.controller = controller }

    // MARK: Timeline (seconds from the start of the story)

    enum T {
        static let working = 1.4
        static let request = 3.0
        static let approveFallback = 7.2       // if the pointer tool isn't driving, approve anyway
        static let terminals = 6.8
        static let openFallback = 9.4
        static let end = 13.8        // the clip is cut earlier; the stage stays up so timing jitter never shows the desktop
    }

    func run() async {
        buildStage()
        seed()
        // The story starts when the recorder signals it is rolling.
        let go = "/tmp/triage-demo-go"
        try? FileManager.default.removeItem(atPath: go)
        try? FileManager.default.removeItem(atPath: "/tmp/triage-demo-t0")
        if CommandLine.arguments.contains("--demo-wait") {
            while !FileManager.default.fileExists(atPath: go) { try? await Task.sleep(for: .milliseconds(50)) }
        } else {
            try? await Task.sleep(for: .seconds(1.5))
        }
        // Sync marker: a white square at the recording's lower-left corner, shown just before the story
        // starts, so the recording script can find the story's start frame exactly (screencapture's start
        // latency varies). It is cut out of every clip: the clip starts after it disappears.
        marker.visible = true
        try? await Task.sleep(for: .seconds(0.35))
        marker.visible = false
        try? await Task.sleep(for: .seconds(1.2))
        t0 = Date()
        try? String(t0.timeIntervalSince1970).write(toFile: "/tmp/triage-demo-t0", atomically: true, encoding: .utf8)

        switch Self.scene {
        case "pill": await runPill()
        case "music": await runMusic()
        default: await runApproval()
        }
        NSApp.presentationOptions = []
        NSApp.terminate(nil)
    }

    private func runApproval() async {
        await at(T.working); startWorking()
        await at(T.request); sendRequest()
        await at(T.approveFallback)
        if model.attention != nil { controller.resolve(approve: true) }
        await at(T.terminals); addTerminals()
        await at(T.openFallback)
        if model.mode == .collapsed { controller.openFromClick() }
        await at(T.end)
    }

    /// The pill alone: cycling, then a request makes it flash red, then it is approved.
    private func runPill() async {
        await at(2.4); startWorking()
        await at(3.8); sendRequest()
        await at(7.0); controller.resolve(approve: true)
        await at(11.2)
    }

    /// A Live Activity (music) opens in the island; the pill slides aside, then back.
    private func runMusic() async {
        startWorking()
        await at(1.8); setMusic(true)
        await at(5.2); setMusic(false)
        await at(9.4)
    }

    private func setMusic(_ on: Bool) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) {
            island.width = on ? 137 : 59
            model.measuredIslandWidth = on ? 137 : 58
        }
    }

    private func at(_ seconds: Double) async {
        let wait = seconds - Date().timeIntervalSince(t0)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
    }

    // MARK: Fake data

    private func seed() {
        model.sessions = [
            Session(externalID: "demo-api", name: "api-server", source: .claudeCode, state: .idle,
                    detail: "Ready", hostBundleID: "com.mitchellh.ghostty"),
            Session(externalID: "demo-web", name: "web-app", source: .claudeCode, state: .done,
                    detail: "Finished 4m ago", lastActivity: Date().addingTimeInterval(-240),
                    hostBundleID: "com.todesktop.230313mzl4w4u92"),
            Session(externalID: "demo-docs", name: "docs-site", source: .claudeCode, state: .idle,
                    detail: "Ready", hostBundleID: "com.mitchellh.ghostty"),
        ]
        model.terminals = []
        model.pillWidthMode = .auto
        model.measuredIslandWidth = 58           // the idle hardware island, no screen capture needed
    }

    private func startWorking() {
        guard let i = model.sessions.firstIndex(where: { $0.externalID == "demo-api" }) else { return }
        model.sessions[i].state = .running
        model.sessions[i].turnStartedAt = Date().addingTimeInterval(-52)
        model.sessions[i].detail = "Editing auth.ts"
    }

    private func sendRequest() {
        let json = """
        {"hook_event_name":"PermissionRequest","session_id":"demo-api","cwd":"/Users/dev/api-server",
         "tool_name":"Edit","tool_input":{"file_path":"/Users/dev/api-server/src/auth.ts",
         "old_string":"const TOKEN_TTL = 3600","new_string":"const TOKEN_TTL = Number(env.TOKEN_TTL ?? 3600)",
         "description":"Make the token expiry configurable"}}
        """
        guard let event = HookEvent.decode(Data(json.utf8)) else { return }
        _ = model.addPermission(event, release: {}) { [weak self] approve in
            guard approve, let self, let i = self.model.sessions.firstIndex(where: { $0.externalID == "demo-api" }) else { return }
            self.model.sessions[i].detail = "Running: npm test"
        }
        if !model.pending.isEmpty { model.pending[0].location = "api-server · main" }
        controller.attentionArrived()
    }

    private func addTerminals() {
        model.terminals = [
            terminal("web-app", "npm run dev", running: 724, host: "com.mitchellh.ghostty"),
            terminal("api-server", "docker compose up", running: 11_520, host: "com.mitchellh.ghostty"),
        ]
    }

    private func terminal(_ name: String, _ command: String, running seconds: TimeInterval, host: String) -> Session {
        var s = Session(name: name, source: .terminal, state: .running, detail: command,
                        lastActivity: Date().addingTimeInterval(-seconds), hostBundleID: host)
        s.turnStartedAt = Date().addingTimeInterval(-seconds)
        return s
    }

    // MARK: Stage

    private func buildStage() {
        guard let screen = IslandGeometry.preferredScreen() else { return }
        NSApp.setActivationPolicy(.regular)
        let w = StageWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .floating
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false
        w.acceptsMouseMovedEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let center = (screen.frame.midX - screen.frame.minX) / screen.frame.width
        let cutoutMid = IslandGeometry.compute(for: screen).cutout.midX - screen.frame.minX
        w.contentView = NSHostingView(rootView: StageView(centerX: center, islandMidX: cutoutMid, island: island, marker: marker))
        w.setFrame(screen.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]
        stage = w
    }
}

/// Lets the stage cover the whole screen, including the menu bar and notch band.
private final class StageWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
}

@MainActor @Observable
final class DemoMarker { var visible = false }

@MainActor @Observable
final class DemoIsland {
    /// Width of the (stand-in) Live Activity over the hardware island; 59 is the idle island.
    var width: CGFloat = 59
}

/// A dark backdrop with a soft spotlight where the card opens, so the black pill and island read
/// clearly, plus a stand-in for the system's Live Activity (widening island with cover art and a waveform).
private struct StageView: View {
    let centerX: CGFloat
    let islandMidX: CGFloat
    let island: DemoIsland
    let marker: DemoMarker

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.035, green: 0.04, blue: 0.055)
            RadialGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.27).opacity(0.9), .clear],
                           center: UnitPoint(x: centerX, y: 0.12), startRadius: 0, endRadius: 520)
            if island.width > 62 { liveActivity }
            // 12pt square at (8, 90) from the recording region's top-left (the region is 720pt wide, centered on the island).
            if marker.visible {
                Rectangle().fill(Color.white).frame(width: 12, height: 12)
                    .position(x: islandMidX - 360 + 8 + 6, y: 90 + 6)
            }
        }
        .ignoresSafeArea()
    }

    private var liveActivity: some View {
        let open = min(max((island.width - 62) / 60, 0), 1)          // 0 -> 1 as it widens
        return ZStack {
            Capsule(style: .continuous).fill(Color.black)
            HStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.28, blue: 0.85), Color(red: 0.13, green: 0.74, blue: 0.80)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 23, height: 23)
                Spacer()
                Waveform()
            }
            .padding(.horizontal, 12)
            .opacity(open)
        }
        .frame(width: island.width, height: 33)
        .position(x: islandMidX, y: 8 + 16.5)
    }
}

/// Five bars that move, like the Music Live Activity's waveform.
private struct Waveform: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    let h = 6 + 11 * abs(sin(t * 4.2 + Double(i) * 0.9))
                    Capsule().fill(Color(red: 0.36, green: 0.78, blue: 0.95)).frame(width: 2.8, height: h)
                }
            }
            .frame(height: 19)
        }
    }
}
