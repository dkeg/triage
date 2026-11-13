import SwiftUI
import ServiceManagement
import TriageCore

struct SettingsView: View {
    @AppStorage(Pref.hoverOpen) private var hoverOpen = true
    @AppStorage(Pref.hoverDelay) private var hoverDelay = 0.25
    @AppStorage(Pref.autoOpenOnAttention) private var autoOpen = true
    @AppStorage(Pref.autoCollapseSeconds) private var autoCollapse = 12.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hooksInstalled = HookInstaller.isInstalled()
    @State private var hookError: String?

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Open on hover", isOn: $hoverOpen)
                LabeledContent("Hover delay") {
                    Slider(value: $hoverDelay, in: 0...1) { Text("") }.frame(width: 160)
                    Text(String(format: "%.2fs", hoverDelay)).monospacedDigit().frame(width: 48)
                }.disabled(!hoverOpen)
                Toggle("Auto-open when a session needs me", isOn: $autoOpen)
                LabeledContent("Auto-close after") {
                    Slider(value: $autoCollapse, in: 3...60, step: 1) { Text("") }.frame(width: 160)
                    Text("\(Int(autoCollapse))s").monospacedDigit().frame(width: 48)
                }.disabled(!autoOpen)
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
                Text("Adds Triage's entries to ~/.claude/settings.json and leaves your other hooks untouched. A one-time backup is saved as settings.json.triage-backup.")
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
        .onAppear { hooksInstalled = HookInstaller.isInstalled() }
        .frame(width: 460, height: 460)
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
