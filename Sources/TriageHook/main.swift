import Foundation
import TriageCore

signal(SIGPIPE, SIG_IGN)

// Management subcommands: `triage-hook install | uninstall | status`
if let cmd = CommandLine.arguments.dropFirst().first {
    switch cmd {
    case "install":
        do {
            let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let helper = try HookInstaller.installHelper(from: me)
            try HookInstaller.install(helper: helper)
            print("Installed hooks into \(HookInstaller.defaultSettingsURL.path)\nHelper: \(helper.path)")
        } catch { FileHandle.standardError.write(Data("install failed: \(error.localizedDescription)\n".utf8)); exit(1) }
    case "uninstall":
        do { try HookInstaller.uninstall(); print("Removed triage hooks.") }
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
