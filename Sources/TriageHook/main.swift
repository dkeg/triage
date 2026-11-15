import Foundation
import TriageCore

signal(SIGPIPE, SIG_IGN)

/// Records, in the app's preferences, whether the user removed the hooks on purpose (so the app
/// doesn't offer to reconnect them). Writes the app's domain directly: the helper lives inside the
/// app bundle, where UserDefaults(suiteName:) with the app's own id is rejected.
func setReconnectDeclined(_ declined: Bool) {
    let app = TriagePaths.bundleID as CFString
    CFPreferencesSetAppValue(TriagePaths.hooksDeclinedKey as CFString, declined as CFBoolean, app)
    CFPreferencesAppSynchronize(app)
}

// Management subcommands: `triage-hook install | uninstall | status`
if let cmd = CommandLine.arguments.dropFirst().first {
    switch cmd {
    case "install":
        do {
            // argv[0] is only "triage-hook" when run via PATH, so ask the system for the real path.
            let me = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
            let helper = try HookInstaller.installHelper(from: me)
            try HookInstaller.install(helper: helper)
            setReconnectDeclined(false)
            print("Installed hooks into \(HookInstaller.defaultSettingsURL.path)\nHelper: \(helper.path)")
        } catch { FileHandle.standardError.write(Data("install failed: \(error.localizedDescription)\n".utf8)); exit(1) }
    case "uninstall":
        do {
            try HookInstaller.uninstall()
            setReconnectDeclined(true)
            print("Removed triage hooks.")
        }
        catch { FileHandle.standardError.write(Data("uninstall failed: \(error.localizedDescription)\n".utf8)); exit(1) }
    case "status":
        print(HookInstaller.isInstalled() ? "installed" : "not installed")
    default:
        FileHandle.standardError.write(Data("usage: triage-hook [install|uninstall|status]\n".utf8)); exit(2)
    }
    exit(0)
}

// Hook mode (invoked by Claude Code): forward the payload to the Triage app and print its
// decision, if any. If Triage isn't running this does nothing and exits 0, so Claude Code
// behaves exactly as if the hook weren't installed.
let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty else { exit(0) }
if let reply = HookClient.send(HookClient.enrich(input)), !reply.isEmpty {
    FileHandle.standardOutput.write(reply)
}
exit(0)
