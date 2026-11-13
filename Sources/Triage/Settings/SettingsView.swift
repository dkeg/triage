import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(Pref.hoverOpen) private var hoverOpen = true
    @AppStorage(Pref.hoverDelay) private var hoverDelay = 0.25
    @AppStorage(Pref.autoOpenOnAttention) private var autoOpen = true
    @AppStorage(Pref.autoCollapseSeconds) private var autoCollapse = 12.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 340)
    }
}
