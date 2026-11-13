import SwiftUI

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
    var name: String
    var source: SessionSource
    var state: SessionState
    var detail: String

    init(id: UUID = UUID(), name: String, source: SessionSource, state: SessionState, detail: String) {
        self.id = id; self.name = name; self.source = source; self.state = state; self.detail = detail
    }
}

struct AttentionRequest: Equatable {
    var sessionID: UUID
    var title: String
    var detail: String
}
