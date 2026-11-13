import SwiftUI
import TriageCore
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
    /// One-time offer to add the Claude Code hooks, so a fresh install (e.g. from Homebrew) works.
    private func offerHookSetup() {
        let key = "hookSetupOffered"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundleURL.pathExtension == "app",
              !HookInstaller.isInstalled() else { return }
        UserDefaults.standard.set(true, forKey: key)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Connect triage to Claude Code?"
        alert.informativeText = "triage shows your Claude Code sessions and permission requests by adding hook entries to ~/.claude/settings.json. Your existing hooks are left alone and a backup is saved next to the file. You can do this later in Settings."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookSetup.installFromBundle() } catch {
            let failed = NSAlert()
            failed.messageText = "Couldn't connect to Claude Code"
            failed.informativeText = error.localizedDescription
            failed.runModal()
        }
    }

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
            offerHookSetup()
            offerLaunchAtLogin()
            // Dev hook: a pending request that stays collapsed (shows the flashing pill).
            if CommandLine.arguments.contains("--demo-pending") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    IslandController.shared.model.simulateAttention()
                }
            }
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
