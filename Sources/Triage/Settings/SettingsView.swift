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
                            if !CGRequestScreenCaptureAccess() {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                            }
                            screenAccess = SystemIslandProbe.hasPermission
                        }
                    }
                    Text("Until it's granted, Auto behaves like Wide. After granting, re-select Auto or relaunch triage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        .frame(width: 460, height: 780)
    }

    private func install() {
        do {
            guard let exe = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("triage-hook"),
                  FileManager.default.isExecutableFile(atPath: exe.path) else {
                throw NSError(domain: "Triage", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "triage-hook helper not found next to the app executable"])
            }
            let helper = try HookInstaller.installHelper(from: exe)
            try HookInstaller.install(helper: helper)
            hookError = nil
        } catch { hookError = error.localizedDescription }
        hooksInstalled = HookInstaller.isInstalled()
    }

    private func remove() {
        do { try HookInstaller.uninstall(); hookError = nil } catch { hookError = error.localizedDescription }
        hooksInstalled = HookInstaller.isInstalled()
    }
}
