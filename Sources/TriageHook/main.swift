import Foundation
import TriageCore

// Claude Code hook command: forwards the hook payload to the Triage app and prints its
// decision (if any). If Triage isn't running this does nothing and exits 0, so Claude Code
// behaves exactly as if the hook weren't installed.
signal(SIGPIPE, SIG_IGN)
let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty else { exit(0) }
if let reply = HookClient.send(HookClient.enrich(input)), !reply.isEmpty {
    FileHandle.standardOutput.write(reply)
}
exit(0)
