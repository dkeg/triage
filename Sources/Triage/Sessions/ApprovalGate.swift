import Foundation

enum ApprovalGate {
    /// Hosts where Claude Code shows its own permission prompt when a hook returns no decision.
    /// Anything else (Subspace/SDK-driven sessions, editors, unknown apps) may treat "no
    /// decision" as a denial, so Triage must never answer with nothing for those.
    static let nativePromptHosts: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "fun.tw93.kaku", "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
    ]

    /// Developer override for experiments: `defaults write app.triage.Triage nativePromptHostsExtra -array <bundle id>`.
    private static var extraHosts: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "nativePromptHostsExtra") ?? [])
    }

    static func canHandBack(hostBundleID: String?) -> Bool {
        hostBundleID.map { nativePromptHosts.contains($0) || extraHosts.contains($0) } ?? false
    }

    /// True when a permission request should NOT go to the island: the app that sent it is the
    /// frontmost app and shows its own prompt, so the user is looking at it.
    static func shouldBypass(enabled: Bool, hostBundleID: String?, frontmostBundleID: String?) -> Bool {
        enabled && canHandBack(hostBundleID: hostBundleID) && hostBundleID == frontmostBundleID
    }
}
