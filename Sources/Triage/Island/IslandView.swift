import SwiftUI
import TriageCore

struct IslandView: View {
    @Bindable var model: IslandModel
    var onResolve: (Bool) -> Void = { _ in }
    var onSkip: () -> Void = {}
    var onAlways: () -> Void = {}
    var onOpen: () -> Void = {}
    var onJump: (Session) -> Void = { _ in }

    var body: some View {
        let size = model.size
        let shape = RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
        Group {
            if model.mode == .collapsed {
                // One status pill beside the hardware island; the rest of the frame is clear.
                StatusPill(model: model, onOpen: onOpen)
                    .frame(width: size.width, height: size.height)
            } else {
                ZStack(alignment: .top) {
                    shape.fill(Color.black)
                    content
                        .id(model.mode)
                        .transition(.opacity)
                        .padding(.top, model.bandHeight)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                // Thin rim, like the system island shows when a Live Activity is active.
                .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
            }
        }
        .opacity(size == .zero ? 0 : 1)
        .padding(.top, model.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.mode)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.centerReserve)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.pending.count)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.sessions)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .collapsed: EmptyView()
        case .peek: PeekContent(model: model)
        case .expanded: ExpandedContent(model: model, onResolve: onResolve, onSkip: onSkip, onAlways: onAlways, onJump: onJump)
        }
    }
}

/// A status dot; pulses when something is blocked on you.
private struct PulsingDot: View {
    let color: Color
    let pulsing: Bool
    @State private var dim = false

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .opacity(pulsing && dim ? 0.3 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

private struct PeekContent: View {
    let model: IslandModel
    var body: some View {
        HStack(spacing: 8) {
            PulsingDot(color: model.pending.count > 0 ? .red : model.needsInputCount > 0 ? .orange : .green,
                       pulsing: model.needsInputCount > 0)
            Text(model.waitingCount > 0
                 ? "\(model.waitingCount) waiting on you"
                 : "\(model.sessions.count) sessions running")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
    }
}

private struct ExpandedContent: View {
    @Bindable var model: IslandModel
    let onResolve: (Bool) -> Void
    let onSkip: () -> Void
    let onAlways: () -> Void
    let onJump: (Session) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { SettingsWindow.show() } label: {
                    Image(systemName: "gearshape").foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .frame(height: 44)

            if let a = model.attention {
                AttentionCard(request: a, more: model.pending.count - 1,
                              approve: { onResolve(true) },
                              deny: { onResolve(false) }, skip: onSkip, always: onAlways)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if model.sessions.isEmpty && model.terminals.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else if model.twoColumns {
                HStack(alignment: .top, spacing: 6) {
                    SessionSection(title: "Agents", model: model, list: model.sessions, compact: true, active: model.activeAgentCount, onJump: onJump)
                    SessionSection(title: "Terminals", model: model, list: model.terminals, compact: true, onJump: onJump)
                }
                .padding(.horizontal, 8)
            } else {
                // One column: agents, then terminals (either may be empty).
                VStack(spacing: 0) {
                    if !model.sessions.isEmpty {
                        SessionSection(title: "Agents", model: model, list: model.sessions, compact: false, active: model.activeAgentCount, onJump: onJump)
                    }
                    if !model.terminals.isEmpty {
                        SessionSection(title: "Terminals", model: model, list: model.terminals, compact: false, onJump: onJump)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }
}

/// A titled group of rows, limited to `rowsPerSection` with a "+N more" line.
private struct SessionSection: View {
    let title: String
    let model: IslandModel
    let list: [Session]
    let compact: Bool
    /// Shown after the total as "· N active" when above zero (agents only).
    var active: Int? = nil
    let onJump: (Session) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                Text("\(list.count)").font(.system(size: 10, weight: .medium).monospacedDigit())
                if let active, active > 0 {
                    Text("· \(active) active").font(.system(size: 10, weight: .medium).monospacedDigit())
                }
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, compact ? 14 : 24)
            .frame(height: IslandModel.sectionHeaderHeight, alignment: .bottom)
            ForEach(model.visible(list)) { s in
                SessionRow(session: s, compact: compact) { onJump(s) }
            }
            if model.overflow(list) > 0 {
                Text("+\(model.overflow(list)) more")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, compact ? 14 : 24)
                    .frame(height: IslandModel.overflowRowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct AttentionCard: View {
    let request: AttentionRequest
    let more: Int
    let approve: () -> Void
    let deny: () -> Void
    let skip: () -> Void
    let always: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HostIcon(bundleID: request.hostBundleID, fallback: nil, size: 14)
                Text(request.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                Spacer(minLength: 8)
                if let loc = request.location {
                    Text(loc).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
            }
            if let note = request.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
            }
            Text(request.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
            if !request.preview.isEmpty { DiffPreview(lines: request.preview) }
            HStack(spacing: 8) {
                Button("Deny", action: deny).buttonStyle(.bordered)
                Button("Approve", action: approve).buttonStyle(.borderedProminent).tint(.orange)
                if request.allowAlways != nil {
                    Button("Always allow", action: always).buttonStyle(.bordered)
                        .help(request.alwaysSummary ?? "Remember this choice")
                }
                if request.canHandBack {
                    Button("Skip", action: skip).buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.55)).help("Answer in the terminal's own prompt instead")
                }
                Spacer()
                if more > 0 {
                    Text("+\(more) more").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
    }
}

/// Before/after lines for edits and writes.
private struct DiffPreview: View {
    let lines: [DiffLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(prefix(line.kind) + line.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(color(line.kind))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .frame(height: 14)
                    .background(background(line.kind))
            }
        }
        .padding(.vertical, 2)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.35)))
    }
    private func prefix(_ k: DiffLine.Kind) -> String { k == .added ? "+ " : k == .removed ? "- " : "  " }
    private func color(_ k: DiffLine.Kind) -> Color {
        k == .added ? Color(red: 0.55, green: 0.9, blue: 0.6) : k == .removed ? Color(red: 1, green: 0.6, blue: 0.6) : .white.opacity(0.5)
    }
    private func background(_ k: DiffLine.Kind) -> Color {
        k == .added ? .green.opacity(0.12) : k == .removed ? .red.opacity(0.12) : .clear
    }
}

private struct SessionRow: View {
    let session: Session
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 10 : 12) {
                HostIcon(bundleID: session.hostBundleID, fallback: session.source.symbol, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    Text(session.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer()
                if hovering {
                    Image(systemName: "arrow.up.forward.app").foregroundStyle(.white.opacity(0.6))
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(session.state.color).frame(width: 6, height: 6)
                        StateLabel(session: session, compact: compact)
                    }
                }
            }
            .padding(.horizontal, compact ? 12 : 22)
            .frame(height: IslandModel.rowHeight)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hovering ? 0.07 : 0)).padding(.horizontal, compact ? 2 : 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Jump to this session")
    }
}

/// "Working 3m 12s" while a turn runs, "Done 2m ago" afterwards.
private struct StateLabel: View {
    let session: Session
    var compact = false
    var body: some View {
        Group {
            if session.state == .running, let start = session.turnStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let t = Activity.elapsed(ctx.date.timeIntervalSince(start))
                    Text(compact ? t : "\(session.source == .terminal ? "Running" : "Working") \(t)")
                }
            } else if session.state == .done {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    let t = Activity.ago(ctx.date.timeIntervalSince(session.lastActivity))
                    Text(compact ? t : "Done \(t)")
                }
            } else {
                Text(session.state.label)
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        .lineLimit(1)
    }
}

/// The icon of the app hosting a session; an SF Symbol when the app is unknown.
private struct HostIcon: View {
    let bundleID: String?
    let fallback: String?
    let size: CGFloat
    var body: some View {
        if let img = HostApp.icon(for: bundleID) {
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else if let fallback {
            Image(systemName: fallback).frame(width: size).foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// The collapsed pill: a single status pill beside the hardware island. It rotates
/// between "All clear" and "N working"; anything that needs you (pending approval, waiting
/// question) takes it over and stays put.
private struct StatusPill: View {
    let model: IslandModel
    let onOpen: () -> Void

    var body: some View {
        let pill = FlashingPill(width: IslandModel.wing, height: model.bandHeight,
                                flashing: model.pending.count > 0, onOpen: onOpen,
                                content: StatusRotator(model: model))
        let clear = Color.clear.frame(width: IslandModel.wing, height: 1)   // keeps the island centered
        HStack(spacing: 0) {
            if model.pillSide == .left {
                pill
                Spacer(minLength: 0).frame(width: model.centerReserve)
                clear
            } else {
                clear
                Spacer(minLength: 0).frame(width: model.centerReserve)
                pill
            }
        }
    }
}

/// What the pill says. Urgent states are fixed; the idle ones alternate every few seconds.
private struct StatusRotator: View {
    let model: IslandModel
    private var interval: TimeInterval { max(model.rotateInterval, 1) }

    private struct Line {
        let text: String
        let color: Color
        let dot: Color
        var pulsing = false
    }

    private var lines: [Line] {
        model.pillStatuses.map { status in
            switch status {
            case .pending: Line(text: status.text, color: .red, dot: .red, pulsing: true)
            case .waiting: Line(text: status.text, color: .orange, dot: .orange, pulsing: true)
            case .allClear: Line(text: status.text, color: .white.opacity(0.9), dot: .green)
            case .active(let n): Line(text: status.text, color: .white.opacity(n > 0 ? 0.75 : 0.5), dot: n > 0 ? .green : .gray)
            }
        }
    }

    var body: some View {
        let lines = self.lines
        if lines.count == 1 {
            row(lines[0])
        } else {
            TimelineView(.periodic(from: .now, by: interval)) { ctx in
                let i = Int(ctx.date.timeIntervalSinceReferenceDate / interval) % lines.count
                ZStack {
                    row(lines[i])
                        .id(i)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
                .animation(.easeInOut(duration: 0.45), value: i)
            }
            .clipped()
        }
    }

    private func row(_ l: Line) -> some View {
        HStack(spacing: 7) {
            PulsingDot(color: l.dot, pulsing: l.pulsing)
            Text(l.text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(l.color)
                .lineLimit(1)
        }
    }
}

/// One wing pill. While `flashing` it pulses red (a request is waiting on you); otherwise it
/// has the system island's plain thin rim.
private struct FlashingPill<C: View>: View {
    let width: CGFloat
    let height: CGFloat
    let flashing: Bool
    let onOpen: () -> Void
    let content: C
    @State private var on = false

    var body: some View {
        let shape = Capsule(style: .continuous)
        content
            .frame(width: width, height: height)
            .background(shape.fill(Color.black))
            .background(shape.fill(Color.red.opacity(flashing ? (on ? 0.35 : 0.05) : 0)))
            .overlay(shape.strokeBorder(flashing ? Color.red.opacity(on ? 0.95 : 0.35) : Color.white.opacity(0.2),
                                        lineWidth: flashing ? 2 : 1.5))
            // Flat like the hardware island; only the pending alert glows.
            .shadow(color: flashing ? Color.red.opacity(on ? 0.6 : 0.1) : .clear, radius: flashing ? 10 : 0, y: flashing ? 3 : 0)
            .contentShape(shape)
            .onTapGesture(perform: onOpen)
            .onAppear { restart() }
            .onChange(of: flashing) { _, _ in restart() }
    }

    private func restart() {
        on = false
        guard flashing else { return }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = true }
    }
}
