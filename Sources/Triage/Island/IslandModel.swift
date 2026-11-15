import SwiftUI
import Observation
import TriageCore

enum IslandMode: Equatable { case collapsed, peek, expanded }

/// What the collapsed pill can say. Urgent states stand alone; otherwise it alternates between
/// "All clear" and the number of active agents (even when that is 0).
enum PillStatus: Equatable {
    case pending(Int), waiting(Int), allClear, active(Int)

    var text: String {
        switch self {
        case .pending(let n): "\(n) pending"
        case .waiting(let n): "\(n) waiting"
        case .allClear: "All clear"
        case .active(let n): "\(n) active"
        }
    }
}

/// How the open card arranges agents and terminals when both are present.
enum CardLayout: String, CaseIterable, Identifiable {
    /// Agents on the left, terminals on the right (a wider card).
    case sideBySide
    /// One column: agents, then terminals below them.
    case single
    var id: String { rawValue }
    var label: String { self == .sideBySide ? "Side by side" : "Single column" }
}

/// Which side of the hardware island the status pill sits on.
enum PillSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "Left" : "Right" }
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
    /// Running terminals (tabs with something in the foreground), kept apart from agent sessions.
    var terminals: [Session] = []
    /// Most rows shown in each section of the open card.
    var rowsPerSection = 4
    var cardLayout: CardLayout = .sideBySide
    var pillSide: PillSide = .left
    /// Seconds between "All clear" and "N working".
    var rotateInterval: TimeInterval = 3.5
    /// System island width measured by the probe (Auto mode), in points.
    var measuredIslandWidth: CGFloat?
    /// The system island is showing something large (Spotlight/Siri): hide the pill meanwhile.
    var yielding = false

    /// Menu bar icons (for example ones a menu-bar manager reveals) are showing where the pill would
    /// be, so it steps aside until they go away.
    var menuIconsOverlap = false
    private var iconStreak = 0
    static let iconEdgeThreshold = 40

    /// Feeds the number of icon edges seen under the pill. The state flips only after two agreeing
    /// samples, so one odd frame doesn't make the pill flicker.
    func ingestIconEdges(_ count: Int) {
        let present = count >= Self.iconEdgeThreshold
        if present == menuIconsOverlap { iconStreak = 0; return }
        iconStreak += 1
        if iconStreak >= 2 { menuIconsOverlap = present; iconStreak = 0 }
    }

    /// Where the collapsed pill is, in the probe's strip coordinates (points, origin top-left).
    func pillRectInStrip(stripWidth: CGFloat) -> CGRect {
        let half = centerReserve / 2
        let x = pillSide == .left ? stripWidth / 2 - half - Self.wing : stripWidth / 2 + half
        return CGRect(x: x, y: topInset, width: Self.wing, height: Self.pillHeight)
    }

    /// Reading waiting for a second confirmation before it is applied (see `ingestIslandReading`).
    private var pendingIslandReading: CGFloat?

    /// Feeds one measurement of the system island's width. Widening is applied at once, so the pill
    /// moves aside the moment something (charging, Music, a timer) opens the island. Narrowing, and
    /// anything huge (Spotlight/Siri), needs two agreeing readings, so a value caught mid-animation
    /// can't stick. A nil reading changes nothing.
    func ingestIslandReading(_ reading: CGFloat?) {
        guard let w = reading else { return }
        func accept() { measuredIslandWidth = w; pendingIslandReading = nil; yielding = w > 420 }
        guard let current = measuredIslandWidth else { accept(); return }
        if abs(w - current) < 4 { pendingIslandReading = nil; return }
        if w > current && w <= 420 { accept(); return }
        if let p = pendingIslandReading, abs(p - w) < 6 { accept() } else { pendingIslandReading = w }
    }
    /// Agent sessions that are working or waiting on you (shown in the Agents header).
    var activeAgentCount: Int { sessions.filter { $0.state == .running || $0.state == .needsInput }.count }

    /// The statuses the pill shows: one fixed urgent state, or the idle pair that it alternates between.
    var pillStatuses: [PillStatus] {
        if !pending.isEmpty { return [.pending(pending.count)] }
        if needsInputCount > 0 { return [.waiting(needsInputCount)] }
        return [.allClear, .active(activeAgentCount)]
    }

    /// What the pill calls "waiting": approvals and questions, i.e. an agent blocked on you.
    /// (Finished sessions awaiting your next prompt deliberately don't count.)
    var needsInputCount: Int { sessions.filter { $0.state == .needsInput }.count }
    var waitingCount: Int { needsInputCount }

    /// The hardware island floats about this far below the top screen edge; we match it.
    static let baseTopInset: CGFloat = 8
    /// Fixed pill height, so moving the pill never resizes it.
    static let pillHeight: CGFloat = 33
    /// How far the pill is nudged up from its base position, in points (0.5pt = 1 physical pixel).
    var pillNudge: CGFloat = 0
    var topInset: CGFloat { Self.baseTopInset - pillNudge }
    /// Width reserved in the middle for the hardware island, including a system Live Activity.
    static let wideReserve: CGFloat = 150
    static let wing: CGFloat = 96
    static let expandedWidth: CGFloat = 540
    /// Used when agents and terminals are shown side by side.
    static let expandedWidthTwoColumns: CGFloat = 680
    static let rowHeight: CGFloat = 52, sectionHeaderHeight: CGFloat = 26, overflowRowHeight: CGFloat = 22

    /// Rows actually shown per section: the setting, reduced if the card wouldn't fit its panel
    /// (several sections stacked, or a tall approval card on top).
    var effectiveRows: Int {
        let budget = IslandGeometry.canvas.height - bandHeight - 44 - 8 - 12 - (attention.map(Self.cardHeight) ?? 0)
        var r = max(rowsPerSection, 1)
        while r > 1 && contentHeight(rows: r) > budget { r -= 1 }
        return r
    }
    func visible(_ list: [Session]) -> [Session] { Array(list.prefix(effectiveRows)) }
    func overflow(_ list: [Session]) -> Int { max(list.count - effectiveRows, 0) }

    /// Agents on the left, terminals on the right: only when chosen and there is something in both.
    var twoColumns: Bool { cardLayout == .sideBySide && !sessions.isEmpty && !terminals.isEmpty }

    func sectionHeight(_ list: [Session], rows r: Int) -> CGFloat {
        guard !list.isEmpty else { return 0 }
        return Self.sectionHeaderHeight + CGFloat(min(list.count, r)) * Self.rowHeight
            + (list.count > r ? Self.overflowRowHeight : 0)
    }
    func sectionHeight(_ list: [Session]) -> CGFloat { sectionHeight(list, rows: effectiveRows) }

    /// Height of the sessions area for a given row limit.
    func contentHeight(rows r: Int) -> CGFloat {
        if sessions.isEmpty && terminals.isEmpty { return 56 }
        if twoColumns { return max(sectionHeight(sessions, rows: r), sectionHeight(terminals, rows: r)) }
        return sectionHeight(sessions, rows: r) + sectionHeight(terminals, rows: r)
    }

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

    /// Whether a screen point should count as hovering triage. While collapsed, only the status
    /// pill beside the hardware island counts: not the island itself, not the clear space on
    /// its other side.
    func hoverHit(_ point: CGPoint, in rect: CGRect, slack: CGFloat = 0) -> Bool {
        guard rect.insetBy(dx: -slack, dy: -slack).contains(point) else { return false }
        guard mode == .collapsed else { return true }
        let half = centerReserve / 2
        return pillSide == .left ? point.x <= geometry.cutout.midX - half : point.x >= geometry.cutout.midX + half
    }

    /// Height of the band that lines up with the hardware island.
    var bandHeight: CGFloat { Self.pillHeight }

    /// Floating pill size for the current mode. Origin is `topInset` below the screen top.
    var size: CGSize {
        let band = bandHeight
        let wide = centerReserve + Self.wing * 2
        switch mode {
        case .collapsed:
            return yielding || menuIconsOverlap ? .zero : CGSize(width: wide, height: band)
        case .peek:
            return CGSize(width: wide, height: band + 36)
        case .expanded:
            let content = contentHeight(rows: effectiveRows)
            let body = 44 + content + 8
            let card: CGFloat = attention.map(Self.cardHeight) ?? 0
            return CGSize(width: twoColumns ? Self.expandedWidthTwoColumns : Self.expandedWidth, height: band + body + card)
        }
    }

    var cornerRadius: CGFloat { mode == .expanded ? 28 : bandHeight / 2 }

    /// Estimated height of the approval card (the panel is sized from this, so it errs generous).
    static func cardHeight(for r: AttentionRequest) -> CGFloat {
        let charsPerLine = 58.0          // monospaced 12pt in the ~490pt-wide card, with margin
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
