import Foundation

/// Extra context the hook helper attaches: who ran it and from which terminal.
public struct TriageMeta: Decodable, Equatable, Sendable {
    public var ppid: Int?
    public var env: [String: String]?
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

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", cwd, eventName = "hook_event_name", transcriptPath = "transcript_path"
        case toolName = "tool_name", toolInput = "tool_input", message, title
        case notificationType = "notification_type", prompt
        case lastAssistantMessage = "last_assistant_message", source, model
        case sessionTitle = "session_title", triage = "_triage"
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

    public var folderName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public enum HookDecision {
    /// stdout JSON Claude Code expects from a PermissionRequest hook.
    public static func permissionResponse(allow: Bool, message: String? = nil) -> Data {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow, let message { decision["message"] = message }
        let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }
}
