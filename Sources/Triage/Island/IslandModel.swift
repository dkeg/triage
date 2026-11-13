import SwiftUI
import Observation
import TriageCore

enum IslandMode: Equatable { case collapsed, peek, expanded }

/// How the collapsed pill's edge and fill are drawn.
enum RimStyle: String, CaseIterable, Identifiable {
    /// Two separate floating pills either side of the hardware island (clear in the middle),
    /// like a Live Activity.
    case wingsOnly
    /// Rim bright at the outer ends, fading to transparent beside the hardware island.
    case outwardFade
    /// Rim bright beside the hardware island, fading toward the outer ends.
    case inwardFade
    /// Thin rim; the fill goes from semi-transparent inside to solid black at the outer ends.
    case fillFade
    case uniform
    case none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wingsOnly: "Wing pills"
        case .outwardFade: "Outer glow"
        case .inwardFade: "Inner glow"
        case .fillFade: "Fill fade"
        case .uniform: "Uniform"
        case .none: "None"
        }
    }
}

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
    /// What the pill calls "waiting": approvals and questions, i.e. an agent blocked on you.
    /// (Finished sessions awaiting your next prompt deliberately don't count.)
    var needsInputCount: Int { sessions.filter { $0.state == .needsInput }.count }
    var waitingCount: Int { needsInputCount }

    /// The hardware island floats about this far below the top screen edge; we match it.
    static let topInset: CGFloat = 6
    /// Width reserved in the middle for the hardware island, including a system Live Activity.
    static let wideReserve: CGFloat = 150
    static let wing: CGFloat = 80
    /// The right-hand pill sits this much closer to the hardware island than the left one.
    static let rightPillPull: CGFloat = 4
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

    /// Whether a screen point should count as hovering Triage. While collapsed, the middle of
    /// the pill is the hardware/system island, which must not trigger anything: only Triage's
    /// own wings count.
    func hoverHit(_ point: CGPoint, in rect: CGRect, slack: CGFloat = 0) -> Bool {
        guard rect.insetBy(dx: -slack, dy: -slack).contains(point) else { return false }
        guard mode == .collapsed else { return true }
        return abs(point.x - geometry.cutout.midX) >= centerReserve / 2
    }

    /// Height of the band that lines up with the hardware island.
    var bandHeight: CGFloat { max(geometry.cutout.height - Self.topInset + 1, 30) }

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
            let card: CGFloat = attention.map(Self.cardHeight) ?? 0
            return CGSize(width: Self.expandedWidth, height: band + body + card)
        }
    }

    var cornerRadius: CGFloat { mode == .expanded ? 28 : bandHeight / 2 }

    /// Estimated height of the approval card (the panel is sized from this, so it errs generous).
    static func cardHeight(for r: AttentionRequest) -> CGFloat {
        let charsPerLine = 66.0
        let cmdLines = min(max(Int((Double(r.command.count) / charsPerLine).rounded(.up)), 1), 6)
            + max(r.command.filter { $0 == "\n" }.count, 0)
        var h: CGFloat = 12 + 16 + 8            // padding, header, gap
        if r.note != nil { h += 16 }
        h += CGFloat(min(cmdLines, 8)) * 16 + 8
        if !r.preview.isEmpty { h += CGFloat(r.preview.count) * 14 + 16 }
        h += 36                                  // buttons row + bottom padding
        return h
    }

    /// Approves the oldest pending request and remembers it ("Always allow").
    func resolveAlways() {
        guard let req = pending.first, let always = req.allowAlways else { return }
        pending.removeFirst()
        always()
        markResolved(sessionID: req.sessionID)
    }

    /// Answers the oldest pending request.
    func resolve(approve: Bool) {
        guard !pending.isEmpty else { return }
        let req = pending.removeFirst()
        req.decide(approve)
        markResolved(sessionID: req.sessionID)
    }

    /// Demo request for trying the UI: one clearly labelled session, removed when answered.
    func simulateAttention() {
        let demoID = "triage-demo"
        let i: Int
        if let existing = sessions.firstIndex(where: { $0.externalID == demoID }) { i = existing }
        else {
            sessions.append(Session(externalID: demoID, name: "Demo session", source: .claudeCode,
                                    state: .needsInput, detail: "Simulated request"))
            i = sessions.count - 1
        }
        sessions[i].state = .needsInput
        let sid = sessions[i].id
        let done: () -> Void = { [weak self] in self?.sessions.removeAll { $0.id == sid } }
        pending.append(AttentionRequest(
            id: UUID(), sessionID: sid, title: "Sources/Triage/Island/IslandView.swift",
            detail: "Demo session wants to use Edit",
            decide: { _ in done() },
            command: "/Users/you/Projects/triage/Sources/Triage/Island/IslandView.swift",
            note: "Make the wing pills 1px shorter",
            toolName: "Edit",
            preview: [DiffLine(kind: .removed, text: "static let topInset: CGFloat = 5"),
                      DiffLine(kind: .added, text: "static let topInset: CGFloat = 6"),
                      DiffLine(kind: .context, text: "… 2 more lines")],
            location: "triage · main",
            alwaysSummary: "Edit(/Users/you/Projects/triage/**)",
            allowAlways: { done() }))
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
