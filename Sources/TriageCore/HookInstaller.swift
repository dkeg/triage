import Foundation

/// Adds/removes Triage's hook entries in a Claude Code settings.json without touching
/// anything else (other tools' hooks, permissions, plugins, ...).
public enum HookInstaller {
    public static let marker = "triage-hook"

    struct Spec { let event: String; let matcher: String?; let async: Bool }
    static let specs: [Spec] = [
        Spec(event: "SessionStart", matcher: "*", async: true),
        Spec(event: "SessionEnd", matcher: nil, async: true),
        Spec(event: "UserPromptSubmit", matcher: nil, async: true),
        Spec(event: "PreToolUse", matcher: "*", async: true),
        Spec(event: "PostToolUse", matcher: "*", async: true),
        Spec(event: "PostToolUseFailure", matcher: "*", async: true),
        Spec(event: "PermissionRequest", matcher: "*", async: false),   // must block for a decision
        Spec(event: "Notification", matcher: "*", async: true),
        Spec(event: "Stop", matcher: nil, async: true),
    ]

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static func command(helper: URL) -> String {
        "'\(helper.path)' # \(marker)"
    }

    private static func isOurs(_ handler: Any) -> Bool {
        guard let h = handler as? [String: Any], let c = h["command"] as? String else { return false }
        return c.contains(marker)
    }

    private static func load(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Triage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object"])
        }
        return obj
    }

    private static func save(_ obj: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: obj,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Writes a one-time backup next to the settings file before the first modification.
    private static func backupIfNeeded(_ url: URL) throws {
        let backup = url.appendingPathExtension("triage-backup")
        if FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: url, to: backup)
        }
    }

    public static func isInstalled(settings url: URL = defaultSettingsURL) -> Bool {
        guard let obj = try? load(url), let hooks = obj["hooks"] as? [String: Any] else { return false }
        return specs.allSatisfy { spec in
            ((hooks[spec.event] as? [[String: Any]]) ?? []).contains { group in
                ((group["hooks"] as? [Any]) ?? []).contains(where: isOurs)
            }
        }
    }

    /// Idempotent: re-running updates our entries in place and leaves everything else alone.
    public static func install(settings url: URL = defaultSettingsURL, helper: URL) throws {
        try backupIfNeeded(url)
        var obj = try load(url)
        var hooks = (obj["hooks"] as? [String: Any]) ?? [:]
        for spec in specs {
            var groups = (hooks[spec.event] as? [[String: Any]]) ?? []
            groups = strip(groups)
            var handler: [String: Any] = ["type": "command", "command": command(helper: helper)]
            if spec.async { handler["async"] = true }
            var group: [String: Any] = ["hooks": [handler]]
            if let m = spec.matcher { group["matcher"] = m }
            groups.append(group)
            hooks[spec.event] = groups
        }
        obj["hooks"] = hooks
        try save(obj, to: url)
    }

    public static func uninstall(settings url: URL = defaultSettingsURL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var obj = try load(url)
        guard var hooks = obj["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = strip(groups)
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { obj.removeValue(forKey: "hooks") } else { obj["hooks"] = hooks }
        try save(obj, to: url)
    }

    /// Removes our handlers from matcher groups, dropping groups left empty.
    private static func strip(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            var g = group
            let remaining = ((group["hooks"] as? [Any]) ?? []).filter { !isOurs($0) }
            if remaining.isEmpty { return nil }
            g["hooks"] = remaining
            return g
        }
    }

    /// Copies the helper binary somewhere stable (so settings.json never points inside an
    /// app bundle that may move or be upgraded by Homebrew).
    @discardableResult
    public static func installHelper(from source: URL, to dest: URL = TriagePaths.helperURL) throws -> URL {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: source, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }
}
