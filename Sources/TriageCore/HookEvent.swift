import Foundation

/// Extra context the hook helper attaches: who ran it and from which terminal.
public struct TriageMeta: Decodable, Equatable, Sendable {
    public var ppid: Int?
    public var env: [String: String]?
    /// Ancestor processes of the hook, nearest first (used to find the host terminal/app).
    public var chain: [ProcRef]?
    /// Controlling tty of the agent's terminal, when it has one.
    public var tty: String?

    public init(ppid: Int? = nil, env: [String: String]? = nil, chain: [ProcRef]? = nil, tty: String? = nil) {
        self.ppid = ppid; self.env = env; self.chain = chain; self.tty = tty
    }
}

/// A Claude Code hook payload (the union of fields we care about across events).
public struct HookEvent: Decodable, Sendable {
    public var sessionID: String?
    public var cwd: String?
    public var eventName: String
    public var transcriptPath: String?
    public var toolName: String?
    public var toolInput: [String: JSONValue]?
    public var message: String?
    public var title: String?
    public var notificationType: String?
    public var prompt: String?
    public var lastAssistantMessage: String?
    public var source: String?
    public var model: String?
    public var sessionTitle: String?
    public var triage: TriageMeta?
    /// Permission updates Claude Code suggests for "always allow" (PermissionRequest only).
    public var permissionSuggestions: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", cwd, eventName = "hook_event_name", transcriptPath = "transcript_path"
        case toolName = "tool_name", toolInput = "tool_input", message, title
        case notificationType = "notification_type", prompt
        case lastAssistantMessage = "last_assistant_message", source, model
        case sessionTitle = "session_title", triage = "_triage", permissionSuggestions = "permission_suggestions"
    }

    public static func decode(_ data: Data) -> HookEvent? {
        try? JSONDecoder().decode(HookEvent.self, from: data)
    }

    /// One-line description of what the tool is about to do.
    public var toolSummary: String? {
        guard let input = toolInput else { return toolName }
        for key in ["command", "file_path", "path", "url", "pattern", "description"] {
            if let s = input[key]?.stringValue, !s.isEmpty { return s }
        }
        return input.values.compactMap(\.stringValue).first ?? toolName
    }

    /// The tool's own description of what it will do (Bash has one).
    public var toolNote: String? {
        guard let d = toolInput?["description"]?.stringValue, !d.isEmpty else { return nil }
        return d
    }

    /// Full text of what the tool will run or touch, for the approval card.
    public var fullCommand: String {
        guard let input = toolInput else { return toolName ?? "" }
        for key in ["command", "file_path", "path", "url", "pattern", "notebook_path"] {
            if let s = input[key]?.stringValue, !s.isEmpty { return s }
        }
        return toolSummary ?? toolName ?? ""
    }

    /// A short before/after preview for Edit/MultiEdit/Write.
    public var diffPreview: [DiffLine] {
        guard let input = toolInput else { return [] }
        func lines(_ s: String?) -> [String] {
            guard let s, !s.isEmpty else { return [] }
            return s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        var out: [DiffLine] = []
        switch toolName {
        case "Edit":
            out += lines(input["old_string"]?.stringValue).map { DiffLine(kind: .removed, text: $0) }
            out += lines(input["new_string"]?.stringValue).map { DiffLine(kind: .added, text: $0) }
        case "MultiEdit":
            if case .array(let edits)? = input["edits"], case .object(let first)? = edits.first {
                out += lines(first["old_string"]?.stringValue).map { DiffLine(kind: .removed, text: $0) }
                out += lines(first["new_string"]?.stringValue).map { DiffLine(kind: .added, text: $0) }
            }
        case "Write":
            out += lines(input["content"]?.stringValue).map { DiffLine(kind: .added, text: $0) }
        default: break
        }
        let cap = 8
        guard out.count > cap else { return out }
        return Array(out.prefix(cap - 1)) + [DiffLine(kind: .context, text: "… \(out.count - (cap - 1)) more lines")]
    }

    /// Human-readable summary of what "always allow" would remember.
    public var suggestionSummary: String? {
        guard let sugg = permissionSuggestions, !sugg.isEmpty else { return nil }
        var parts: [String] = []
        for case .object(let s) in sugg {
            guard s["type"]?.stringValue == "addRules", case .array(let rules)? = s["rules"] else { continue }
            for case .object(let r) in rules {
                let tool = r["toolName"]?.stringValue ?? "tool"
                if let c = r["ruleContent"]?.stringValue, !c.isEmpty { parts.append("\(tool)(\(c))") } else { parts.append(tool) }
            }
        }
        return parts.isEmpty ? "Remember this choice" : parts.joined(separator: ", ")
    }

    public var folderName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case added, removed, context }
    public var kind: Kind
    public var text: String
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
}

public enum HookDecision {
    /// stdout JSON Claude Code expects from a PermissionRequest hook.
    public static func permissionResponse(allow: Bool, message: String? = nil,
                                          updatedPermissions: [JSONValue]? = nil) -> Data {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow, let message { decision["message"] = message }
        // "Always allow": hand Claude Code's own suggested permission updates back as-is.
        if allow, let updatedPermissions, !updatedPermissions.isEmpty {
            decision["updatedPermissions"] = updatedPermissions.map(\.foundationObject)
        }
        let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }
}
