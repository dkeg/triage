import SwiftUI
import Observation
import TriageCore

enum IslandMode: Equatable { case collapsed, peek, expanded }

/// How wide the collapsed pill is.
enum PillWidthMode: String, CaseIterable, Identifiable {
    /// Hugs the hardware island.
    case compact
    /// Fixed width that clears a system Live Activity (recommended).
    case wide
    /// Follows the system island's real width (needs Screen Recording).
    case auto
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: "Compact"
        case .wide: "Wide (recommended)"
        case .auto: "Auto"
        }
    }
}

@MainActor @Observable
final class IslandModel {
    var mode: IslandMode = .collapsed
    var sessions: [Session] = []
    /// Permission requests waiting on the user, oldest first.
    var pending: [AttentionRequest] = []
    var attention: AttentionRequest? { pending.first }
    var geometry: IslandGeometry = .init(cutout: .zero, screenFrame: .zero, isPhysical: false)

    var pillWidthMode: PillWidthMode = .wide
    /// System island width measured by the probe (Auto mode), in points.
    var measuredIslandWidth: CGFloat?
    /// The system island is showing something large (Spotlight/Siri): hide the pill meanwhile.
    var yielding = false

    var hasActivity: Bool { !sessions.isEmpty }
    var needsInputCount: Int { sessions.filter { $0.state == .needsInput }.count }

    /// The hardware island floats about this far below the top screen edge; we match it.
    static let topInset: CGFloat = 4
    /// Width reserved in the middle for the hardware island, including a system Live Activity.
    static let wideReserve: CGFloat = 150
    static let wing: CGFloat = 80
    static let expandedWidth: CGFloat = 620

    /// Width kept clear in the middle for the system island.
    var centerReserve: CGFloat {
        let hardware = geometry.cutout.width + 10
        switch pillWidthMode {
        case .compact: return hardware
        case .wide: return Self.wideReserve
        case .auto:
            guard let m = measuredIslandWidth else { return Self.wideReserve }   // no reading: be safe
            return max(hardware, m + 16)
        }
    }

    /// Height of the band that lines up with the hardware island.
    var bandHeight: CGFloat { max(geometry.cutout.height - Self.topInset + 2, 30) }

    /// Floating pill size for the current mode. Origin is Self.topInset below the screen top.
    var size: CGSize {
        let band = bandHeight
        let wide = centerReserve + Self.wing * 2
        switch mode {
        case .collapsed:
            return hasActivity && !yielding ? CGSize(width: wide, height: band) : .zero
        case .peek:
            return CGSize(width: wide, height: band + 36)
        case .expanded:
            let rows = min(sessions.count, 5)
            let body = 44 + CGFloat(rows) * 52 + 8
            let card: CGFloat = attention == nil ? 0 : 118
            return CGSize(width: Self.expandedWidth, height: band + body + card)
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
