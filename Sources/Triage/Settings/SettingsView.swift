import SwiftUI
import ServiceManagement
import TriageCore

struct SettingsView: View {
    @AppStorage(Pref.hoverOpen) private var hoverOpen = true
    @AppStorage(Pref.hoverDelay) private var hoverDelay = 0.5
    @AppStorage(Pref.approvalTimeout) private var approvalTimeout = 45.0
    @AppStorage(Pref.autoOpenOnAttention) private var autoOpen = true
    @AppStorage(Pref.autoCollapseSeconds) private var autoCollapse = 5.0
    @AppStorage(Pref.holdWhenFocused) private var holdWhenFocused = true
    @AppStorage(Pref.pillWidth) private var pillWidth = PillWidthMode.wide.rawValue
    @AppStorage(Pref.pillSide) private var pillSide = PillSide.left.rawValue
    @AppStorage(Pref.rotateSeconds) private var rotateSeconds = 3.5
    @AppStorage(Pref.pillNudge) private var pillNudge = 0.0
    @AppStorage(Pref.showTerminals) private var showTerminals = true
    @AppStorage(Pref.showIdleTerminals) private var showIdleTerminals = false
    @AppStorage(Pref.showCommandArguments) private var showCommandArguments = true
    @AppStorage(Pref.rowsPerSection) private var rowsPerSection = 4
    @AppStorage(Pref.cardLayout) private var cardLayout = CardLayout.sideBySide.rawValue
    @AppStorage(Pref.avoidMenuIcons) private var avoidMenuIcons = true
    @State private var screenAccess = SystemIslandProbe.hasPermission
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hooksInstalled = HookInstaller.isInstalled()
    @State private var hookError: String?

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Open on hover", isOn: $hoverOpen)
                LabeledContent("Hover delay") {
                    Slider(value: $hoverDelay, in: 0.1...1.5) { Text("") }.frame(width: 160)
                    Text(String(format: "%.2fs", hoverDelay)).monospacedDigit().frame(width: 48)
                }.disabled(!hoverOpen)
                Toggle("Auto-open when a session needs me", isOn: $autoOpen)
                Toggle("Skip approvals from the app that's in front", isOn: $holdWhenFocused)
                Text("For terminal sessions: if the terminal is in front, triage stays out of the way and you answer in Claude's own prompt. Sessions hosted by other apps (like Subspace) always use the island.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Hand back if unanswered") {
                    Slider(value: $approvalTimeout, in: 15...300, step: 5) { Text("") }.frame(width: 160)
                    Text("\(Int(approvalTimeout))s").monospacedDigit().frame(width: 48)
                }
                Text("Terminal sessions only: an unanswered request goes back to Claude's own prompt after this long. Sessions in other apps (like Subspace) stay in the island until answered.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Auto-close after") {
                    Slider(value: $autoCollapse, in: 3...60, step: 1) { Text("") }.frame(width: 160)
                    Text("\(Int(autoCollapse))s").monospacedDigit().frame(width: 48)
                }.disabled(!autoOpen)
            }
            Section("Appearance") {
                Picker("Collapsed width", selection: $pillWidth) {
                    ForEach(PillWidthMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Pill side", selection: $pillSide) {
                    ForEach(PillSide.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Step aside for menu bar icons", isOn: $avoidMenuIcons)
                Text("When icons (for example ones your menu bar manager reveals) appear where the pill sits, the pill hides until they're gone. Works with Auto width, which is what lets triage see the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Move pill up") {
                    Slider(value: $pillNudge, in: 0...3, step: 0.5) { Text("") }.frame(width: 160)
                    Text(String(format: "%.1fpt", pillNudge)).monospacedDigit().frame(width: 48)
                }
                Text("Fine-tune the pill's height on screen. 0.5pt is one physical pixel; the pill keeps its size.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Cycle every") {
                    Slider(value: $rotateSeconds, in: 1.5...10, step: 0.5) { Text("") }.frame(width: 160)
                    Text(String(format: "%.1fs", rotateSeconds)).monospacedDigit().frame(width: 48)
                }
                Text("The pill alternates between \"All clear\" and \"N working\". Pending approvals and questions always stay on screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    switch PillWidthMode(rawValue: pillWidth) ?? .wide {
                    case .compact: Text("Hugs the hardware island. Status text can sit under the system island while it shows a Live Activity.")
                    case .wide: Text("Fixed width that clears a system Live Activity such as Music or a timer.")
                    case .auto: Text("Widens only when the system island does, and steps aside while Spotlight or Siri is open. triage reads a thin strip of the screen to measure the island's width; nothing is stored or sent.")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if pillWidth == PillWidthMode.auto.rawValue && !screenAccess {
                    HStack {
                        Text("Needs Screen Recording access").foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") {
                            SystemIslandProbe.registerForAccess(activate: true)
                            if !SystemIslandProbe.hasPermission {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                            }
                            screenAccess = SystemIslandProbe.hasPermission
                        }
                    }
                    Text("Until it's granted, Auto behaves like Wide. If macOS doesn't list triage, click + under the list and add it (or drag it in from Finder). Then relaunch triage.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show triage in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }
            Section("Sessions") {
                Toggle("Show running terminals", isOn: $showTerminals)
                Toggle("Include idle terminals", isOn: $showIdleTerminals).disabled(!showTerminals)
                Toggle("Show command arguments", isOn: $showCommandArguments).disabled(!showTerminals)
                Text("A terminal is listed while something is running in it (a build, a server, ssh). Arguments that look like secrets (tokens, passwords, URL credentials) are masked, but the check is a heuristic, so turn arguments off if you share your screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("When both are shown", selection: $cardLayout) {
                    ForEach(CardLayout.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text("Side by side puts agents on the left and terminals on the right (a wider card). Single column stacks them. With only one kind running, the card is always a single column.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Rows per section: \(rowsPerSection)", value: $rowsPerSection, in: 2...8)
            }
            Section("Claude Code") {
                LabeledContent("Hooks") {
                    Text(hooksInstalled ? "Installed" : "Not installed")
                        .foregroundStyle(hooksInstalled ? .green : .secondary)
                }
                HStack {
                    Button(hooksInstalled ? "Reinstall" : "Install Hooks") { install() }
                    if hooksInstalled { Button("Remove") { remove() } }
                }
                Text("Adds triage's entries to ~/.claude/settings.json and leaves your other hooks untouched. A one-time backup is saved as settings.json.triage-backup.")
                    .font(.caption).foregroundStyle(.secondary)
                if let hookError { Text(hookError).font(.caption).foregroundStyle(.red) }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { hooksInstalled = HookInstaller.isInstalled(); screenAccess = SystemIslandProbe.hasPermission }
        .frame(width: 460, height: 1290)
    }

    private func install() {
        do {
            try HookSetup.installFromBundle()
            hookError = nil
        } catch { hookError = error.localizedDescription }
        hooksInstalled = HookInstaller.isInstalled()
    }

    private func remove() {
        do { try HookInstaller.uninstall(); hookError = nil } catch { hookError = error.localizedDescription }
        hooksInstalled = HookInstaller.isInstalled()
    }
}
