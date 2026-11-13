import Foundation

enum Activity {
    /// "Editing IslandView.swift", "Running: swift build", "Searching: TODO" ...
    static func describe(toolName: String?, summary: String?) -> String {
        let target = shorten(summary, toolName: toolName)
        switch toolName ?? "" {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return join("Editing", target)
        case "Read": return join("Reading", target)
        case "Bash": return join("Running:", target)
        case "Grep", "Glob": return join("Searching:", target)
        case "WebFetch": return join("Fetching", target)
        case "WebSearch": return join("Searching the web:", target)
        case "Task", "Agent": return join("Subagent:", target)
        case "TodoWrite": return "Updating todos"
        case "": return target ?? "Working"
        default: return join(toolName!, target)
        }
    }

    private static func join(_ verb: String, _ target: String?) -> String {
        target.map { "\(verb) \($0)" } ?? verb
    }

    /// File paths show just the file name; everything else is trimmed to one short line.
    private static func shorten(_ s: String?, toolName: String?) -> String? {
        guard var t = s?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if ["Edit", "MultiEdit", "Write", "Read", "NotebookEdit"].contains(toolName ?? ""), t.hasPrefix("/") {
            t = URL(fileURLWithPath: t).lastPathComponent
        }
        return t.count > 60 ? String(t.prefix(60)) + "…" : t
    }

    /// 45s, 3m 12s, 1h 5m
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    /// Coarser, for "finished" rows: 12s ago, 3m ago, 2h ago
    static func ago(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
