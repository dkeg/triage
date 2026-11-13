import SwiftUI
import TriageCore

enum SessionSource: String, CaseIterable, Identifiable {
    case claudeCode, supacode, terminal, otherAgent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .supacode: "Supacode"
        case .terminal: "Terminal"
        case .otherAgent: "Agent"
        }
    }
    var symbol: String {
        switch self {
        case .claudeCode: "sparkle"
        case .supacode: "square.stack.3d.up"
        case .terminal: "terminal"
        case .otherAgent: "cpu"
        }
    }
}

enum SessionState: Equatable {
    case running, needsInput, idle, done
    var color: Color {
        switch self {
        case .running: .green
        case .needsInput: .orange
        case .idle: .gray
        case .done: .blue
        }
    }
    var label: String {
        switch self {
        case .running: "Working"
        case .needsInput: "Needs you"
        case .idle: "Idle"
        case .done: "Done"
        }
    }
}

struct Session: Identifiable, Equatable {
    let id: UUID
    /// The agent's own session id (e.g. Claude Code's session_id), used to match hook events.
    var externalID: String?
    var name: String
    var source: SessionSource
    var state: SessionState
    var detail: String
    var lastActivity: Date
    /// Working directory and terminal context, used to jump back to the session.
    var cwd: String?
    var meta: TriageMeta?

    /// The agent process (Claude Code) this session belongs to, from the hook's ancestor chain.
    var agentPID: Int? { meta?.chain?.first(where: { $0.name == "claude" })?.pid }

    init(id: UUID = UUID(), externalID: String? = nil, name: String, source: SessionSource,
         state: SessionState, detail: String, lastActivity: Date = Date(),
         cwd: String? = nil, meta: TriageMeta? = nil) {
        self.id = id; self.externalID = externalID; self.name = name; self.source = source
        self.state = state; self.detail = detail; self.lastActivity = lastActivity
        self.cwd = cwd; self.meta = meta
    }
}

/// A permission prompt waiting on the user. `decide` answers the blocked hook.
struct AttentionRequest: Identifiable, Equatable {
    let id: UUID
    var sessionID: UUID
    var title: String
    var detail: String
    var decide: (Bool) -> Void
    /// Hands the request back to the app's own prompt (replies with no decision). Only safe
    /// when the host shows a native prompt; elsewhere it can act as a denial.
    var canHandBack = false
    var release: () -> Void = {}

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}
