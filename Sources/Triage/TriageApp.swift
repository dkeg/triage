import SwiftUI

@main
struct TriageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Triage", systemImage: "capsule.tophalf.filled") {
            Button("Toggle Island") { IslandController.shared.toggleVisibility() }
            Button("Simulate Attention") { IslandController.shared.simulateAttention() }
            Divider()
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Triage") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            IslandController.shared.start()
            // Dev hook: `open build/Triage.app --args --demo-attention`
            if CommandLine.arguments.contains("--demo-attention") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    IslandController.shared.simulateAttention()
                }
            }
        }
    }
}
