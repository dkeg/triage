import SwiftUI
import ServiceManagement

@main
struct TriageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("triage", systemImage: "capsule.tophalf.filled") {
            Button("Toggle Island") { IslandController.shared.toggleVisibility() }
            Button("Simulate Request (demo)") { IslandController.shared.simulateAttention() }
            Divider()
            Button("Settings…") { SettingsWindow.show() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit triage") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One-time offer. Without Triage running, hooks do nothing and Claude shows its normal
    /// prompts, so starting at login is what makes approvals in the island dependable.
    private func offerLaunchAtLogin() {
        let key = "launchAtLoginOffered"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundleURL.pathExtension == "app",
              SMAppService.mainApp.status != .enabled else { return }
        UserDefaults.standard.set(true, forKey: key)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Start triage at login?"
        alert.informativeText = "When triage isn't running, nothing is sent to it and permission prompts appear in your agent as usual. Starting at login keeps approvals available in the island. You can change this any time in Settings."
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            do { try SMAppService.mainApp.register() }
            catch { TriageLog.write("launch at login failed: \(error.localizedDescription)") }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            IslandController.shared.start()
            offerLaunchAtLogin()
            // Dev hooks: `open build/Triage.app --args --demo-attention` / `--open-settings`
            if CommandLine.arguments.contains("--open-settings") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    SettingsWindow.show()
                }
            }
            if CommandLine.arguments.contains("--demo-attention") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    IslandController.shared.simulateAttention()
                }
            }
        }
    }
}
