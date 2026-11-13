import SwiftUI
import TriageCore

struct IslandView: View {
    @Bindable var model: IslandModel
    @AppStorage(Pref.rimStyle) private var rimStyleRaw = RimStyle.wingsOnly.rawValue
    private var rimStyle: RimStyle { RimStyle(rawValue: rimStyleRaw) ?? .wingsOnly }
    var onResolve: (Bool) -> Void = { _ in }
    var onSkip: () -> Void = {}
    var onAlways: () -> Void = {}
    var onOpen: () -> Void = {}
    var onJump: (Session) -> Void = { _ in }

    var body: some View {
        let size = model.size
        let shape = RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
        Group {
            if isWingPills {
                // Two separate floating pills either side of the hardware island.
                WingPills(model: model, onOpen: onOpen)
                    .frame(width: size.width, height: size.height)
            } else {
            ZStack(alignment: .top) {
                shape.fill(fill)
                content
                    .id(model.mode)
                    .transition(.opacity)
                    .padding(.top, model.mode == .collapsed ? 0 : model.bandHeight)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            // Thin rim, like the system island shows when a Live Activity is active.
            .overlay(shape.strokeBorder(rim, lineWidth: 1.5))
            .shadow(color: .black.opacity(size == .zero ? 0 : 0.35), radius: 10, y: 4)
            }
        }
        .opacity(size == .zero ? 0 : 1)
        .padding(.top, IslandModel.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.mode)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.centerReserve)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.pending.count)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.sessions)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var isWingPills: Bool { model.mode == .collapsed && rimStyle == .wingsOnly }

    private var wingFraction: CGFloat {
        guard model.size.width > 0 else { return 0.25 }
        return min(IslandModel.wing / model.size.width, 0.45)
    }

    private func horizontal(_ stops: [(Double, CGFloat)]) -> AnyShapeStyle {
        AnyShapeStyle(LinearGradient(stops: stops.map { .init(color: .white.opacity($0.0), location: $0.1) },
                                     startPoint: .leading, endPoint: .trailing))
    }

    /// How far the wings tuck under the system island so no wallpaper shows between them.
    private var tuckFraction: CGFloat {
        model.size.width > 0 ? 6 / model.size.width : 0
    }

    /// Fill: solid black, except while collapsed in "Wings only" (clear behind the hardware
    /// island) or "Fill fade" (transparent inside to opaque outside).
    private var fill: AnyShapeStyle {
        guard model.mode == .collapsed else { return AnyShapeStyle(Color.black) }
        let w = wingFraction
        if rimStyle == .wingsOnly {
            let edge = w + tuckFraction
            return AnyShapeStyle(LinearGradient(
                stops: [.init(color: .black, location: 0),
                        .init(color: .black, location: edge),
                        .init(color: .clear, location: edge + 0.004),
                        .init(color: .clear, location: 1 - edge - 0.004),
                        .init(color: .black, location: 1 - edge),
                        .init(color: .black, location: 1)],
                startPoint: .leading, endPoint: .trailing))
        }
        guard rimStyle == .fillFade else { return AnyShapeStyle(Color.black) }
        return AnyShapeStyle(LinearGradient(
            stops: [.init(color: .black, location: 0),
                    .init(color: .black.opacity(0.55), location: w),
                    .init(color: .black.opacity(0.55), location: 1 - w),
                    .init(color: .black, location: 1)],
            startPoint: .leading, endPoint: .trailing))
    }

    /// Collapsed rim per the chosen style. Expanded always gets a plain uniform rim.
    private var rim: AnyShapeStyle {
        let plain = AnyShapeStyle(Color.white.opacity(0.2))
        guard model.mode == .collapsed, model.size.width > 0 else { return plain }
        let w = wingFraction
        switch rimStyle {
        case .wingsOnly:
            let edge = w + tuckFraction
            return horizontal([(0.5, 0), (0.32, w * 0.55), (0.0, edge), (0.0, 1 - edge), (0.32, 1 - w * 0.55), (0.5, 1)])
        case .uniform: return plain
        case .none: return AnyShapeStyle(Color.clear)
        case .outwardFade:
            return horizontal([(0.55, 0), (0.28, w * 0.5), (0, w), (0, 1 - w), (0.28, 1 - w * 0.5), (0.55, 1)])
        case .inwardFade:
            return horizontal([(0, 0), (0.18, w * 0.5), (0.5, w), (0.5, 1 - w), (0.18, 1 - w * 0.5), (0, 1)])
        case .fillFade:
            return horizontal([(0.3, 0), (0.15, w), (0.15, 1 - w), (0.3, 1)])
        }
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .collapsed: CollapsedContent(model: model)
        case .peek: PeekContent(model: model)
        case .expanded: ExpandedContent(model: model, onResolve: onResolve, onSkip: onSkip, onAlways: onAlways, onJump: onJump)
        }
    }
}

/// Orange (pulsing) when something is blocked on you, blue when a session has finished and is
/// waiting for your next prompt, green otherwise.
private struct StatusDot: View {
    let model: IslandModel
    @State private var dim = false

    private var color: Color {
        model.needsInputCount > 0 ? .orange : model.finishedWaitingCount > 0 ? .blue : .green
    }

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .opacity(model.needsInputCount > 0 && dim ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// "2 waiting" / "All clear"
@MainActor private func waitingText(_ model: IslandModel) -> String {
    model.waitingCount > 0 ? "\(model.waitingCount) waiting" : "All clear"
}

private struct CollapsedContent: View {
    let model: IslandModel
    var body: some View {
                let working = model.sessions.filter { $0.state == .running }.count
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                StatusDot(model: model)
                Text(waitingText(model))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.needsInputCount > 0 ? Color.orange : model.finishedWaitingCount > 0 ? Color.blue.opacity(0.9) : .white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(width: IslandModel.wing, alignment: .center)
            Spacer(minLength: 0).frame(width: model.centerReserve)
            Text("\(working) working")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(width: IslandModel.wing, alignment: .center)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct PeekContent: View {
    let model: IslandModel
    var body: some View {
        HStack(spacing: 8) {
            StatusDot(model: model)
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

            ForEach(model.sessions.prefix(5)) { s in
                SessionRow(session: s) { onJump(s) }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
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
                        StateLabel(session: session)
                    }
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 52)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hovering ? 0.07 : 0)).padding(.horizontal, 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Jump to this session")
    }
}

/// "Working 3m 12s" while a turn runs, "Done 2m ago" afterwards.
private struct StateLabel: View {
    let session: Session
    var body: some View {
        Group {
            if session.state == .running, let start = session.turnStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("Working \(Activity.elapsed(ctx.date.timeIntervalSince(start)))")
                }
            } else if session.state == .done {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Done \(Activity.ago(ctx.date.timeIntervalSince(session.lastActivity)))")
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

/// Collapsed "Wing pills": each side is its own fully rounded pill with the same thin rim as
/// the system island; the middle is left clear for the hardware island.
private struct WingPills: View {
    let model: IslandModel
    let onOpen: () -> Void

    var body: some View {
                let working = model.sessions.filter { $0.state == .running }.count
        HStack(spacing: 0) {
            pill {
                HStack(spacing: 7) {
                    StatusDot(model: model)
                    Text(waitingText(model))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.needsInputCount > 0 ? Color.orange : model.finishedWaitingCount > 0 ? Color.blue.opacity(0.9) : .white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0).frame(width: model.centerReserve)
            pill {
                Text("\(working) working")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .offset(x: -IslandModel.rightPillPull)
        }
    }

    private func pill<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let shape = Capsule(style: .continuous)
        return content()
            .frame(width: IslandModel.wing, height: model.bandHeight)
            .background(shape.fill(Color.black))
            .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .contentShape(shape)
            .onTapGesture(perform: onOpen)
    }
}
