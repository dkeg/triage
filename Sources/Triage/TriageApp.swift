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
    /// Kept alive for the duration of a `--demo-story` run.
    private var demoStory: AnyObject?

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

    /// The helper copy exists only if the user connected before, so hooks missing now were removed
    /// without them asking (for example by an update). Offer to put them back.
    private func offerHookReconnect() {
        guard HookReconnect.shouldOffer(
            isApp: Bundle.main.bundleURL.pathExtension == "app",
            setupOffered: UserDefaults.standard.bool(forKey: "hookSetupOffered"),
            declined: UserDefaults.standard.bool(forKey: Pref.hooksReconnectDeclined),
            helperExists: FileManager.default.fileExists(atPath: TriagePaths.helperURL.path),
            hooksInstalled: HookInstaller.isInstalled()) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reconnect triage to Claude Code?"
        alert.informativeText = "triage's hooks are no longer in ~/.claude/settings.json, so sessions and approvals won't show up. This can happen after an update. Your other hooks aren't touched."
        alert.addButton(withTitle: "Reconnect")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { try HookSetup.installFromBundle() } catch {
                TriageLog.write("reconnect failed: \(error.localizedDescription)")
            }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: Pref.hooksReconnectDeclined)
        default: break
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
        if DemoStory.isEnabled { MainActor.assumeIsolated { DemoStory.installOverrides() } }
        MainActor.assumeIsolated {
            IslandController.shared.start()
            if DemoStory.isEnabled {
                let story = DemoStory(controller: IslandController.shared)
                demoStory = story
                Task { @MainActor in await story.run() }
                return
            }
            offerHookSetup()
            offerHookReconnect()
            offerLaunchAtLogin()
            // Dev hook: just open the card.
            if CommandLine.arguments.contains("--demo-open") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    IslandController.shared.openFromClick()
                }
            }
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
