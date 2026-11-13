import Foundation
import TriageCore

enum HookSetup {
    /// Copies the `triage-hook` helper next to the app to a stable location and adds triage's
    /// entries to ~/.claude/settings.json (other hooks are left alone; a backup is saved once).
    static func installFromBundle() throws {
        guard let exe = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("triage-hook"),
              FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw NSError(domain: "triage", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "triage-hook helper not found next to the app executable"])
        }
        let helper = try HookInstaller.installHelper(from: exe)
        try HookInstaller.install(helper: helper)
    }
}
