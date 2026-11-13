import SwiftUI
import Observation
import TriageCore

enum IslandMode: Equatable { case collapsed, peek, expanded }

@MainActor @Observable
final class IslandModel {
    var mode: IslandMode = .collapsed
    var sessions: [Session] = []
    /// Permission requests waiting on the user, oldest first.
    var pending: [AttentionRequest] = []
    var attention: AttentionRequest? { pending.first }
    var geometry: IslandGeometry = .init(cutout: .zero, screenFrame: .zero, isPhysical: false)

    var hasActivity: Bool { !sessions.isEmpty }
    var needsInputCount: Int { sessions.filter { $0.state == .needsInput }.count }

    /// The hardware island floats about this far below the top screen edge; we match it.
    static let topInset: CGFloat = 4
    /// Width reserved in the middle for the hardware island, including a system Live Activity.
    static let centerReserve: CGFloat = 150
    static let wing: CGFloat = 80

    /// Height of the band that lines up with the hardware island.
    var bandHeight: CGFloat { max(geometry.cutout.height - Self.topInset + 2, 30) }

    /// Floating pill size for the current mode. Origin is Self.topInset below the screen top.
    var size: CGSize {
        let band = bandHeight
        let wide = Self.centerReserve + Self.wing * 2
        switch mode {
        case .collapsed:
            return hasActivity ? CGSize(width: wide, height: band) : .zero
        case .peek:
            return CGSize(width: wide, height: band + 36)
        case .expanded:
            let rows = min(sessions.count, 5)
            let body = 44 + CGFloat(rows) * 52 + 8
            return CGSize(width: 500, height: band + body + (attention == nil ? 0 : 118))
        }
    }

    var cornerRadius: CGFloat { mode == .expanded ? 28 : bandHeight / 2 }

    /// Answers the oldest pending request.
    func resolve(approve: Bool) {
        guard !pending.isEmpty else { return }
        let req = pending.removeFirst()
        req.decide(approve)
        markResolved(sessionID: req.sessionID)
    }

    func simulateAttention() {
        if sessions.isEmpty { sessions = Self.mockSessions() }
        guard let s = sessions.first(where: { $0.source == .claudeCode }) ?? sessions.first,
              let i = sessions.firstIndex(where: { $0.id == s.id }) else { return }
        sessions[i].state = .needsInput
        pending.append(AttentionRequest(
            id: UUID(), sessionID: s.id, title: "rm -rf build && swift build",
            detail: "\(s.name) wants to use Bash", decide: { _ in }))
    }

    static func mockSessions() -> [Session] {
        [
            Session(name: "triage / main", source: .claudeCode, state: .running, detail: "Editing IslandView.swift"),
            Session(name: "fullstack-triage", source: .supacode, state: .idle, detail: "Topic ready"),
            Session(name: "zsh — api", source: .terminal, state: .running, detail: "npm run dev"),
            Session(name: "codex · refactor", source: .otherAgent, state: .done, detail: "Finished 2m ago"),
        ]
    }
}
