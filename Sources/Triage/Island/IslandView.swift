import SwiftUI

struct IslandView: View {
    @Bindable var model: IslandModel
    var onResolve: (Bool) -> Void = { _ in }
    var onSkip: () -> Void = {}
    var onJump: (Session) -> Void = { _ in }

    var body: some View {
        let size = model.size
        let shape = RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(.black)
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

    /// Collapsed: the rim is opaque at the outer ends and fades to transparent where the wing
    /// meets the hardware island, like the island's own rim wrapping a Live Activity. The fade
    /// is anchored to the visible wings, so it is actually visible. Expanded: uniform rim.
    private var rim: AnyShapeStyle {
        guard model.mode == .collapsed, model.size.width > 0 else { return AnyShapeStyle(Color.white.opacity(0.2)) }
        let wing = min(IslandModel.wing / model.size.width, 0.45)
        return AnyShapeStyle(LinearGradient(
            stops: [.init(color: .white.opacity(0.55), location: 0),
                    .init(color: .white.opacity(0.28), location: wing * 0.5),
                    .init(color: .white.opacity(0.0), location: wing),
                    .init(color: .white.opacity(0.0), location: 1 - wing),
                    .init(color: .white.opacity(0.28), location: 1 - wing * 0.5),
                    .init(color: .white.opacity(0.55), location: 1)],
            startPoint: .leading, endPoint: .trailing))
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .collapsed: CollapsedContent(model: model)
        case .peek: PeekContent(model: model)
        case .expanded: ExpandedContent(model: model, onResolve: onResolve, onSkip: onSkip, onJump: onJump)
        }
    }
}

private struct StatusDot: View {
    let needsInput: Bool
    var body: some View {
        Circle().fill(needsInput ? Color.orange : Color.green).frame(width: 7, height: 7)
    }
}

/// Status text sits in the wings, either side of the hardware island.
private struct CollapsedContent: View {
    let model: IslandModel
    var body: some View {
        let waiting = model.needsInputCount
        let working = model.sessions.filter { $0.state == .running }.count
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                StatusDot(needsInput: waiting > 0)
                Text(waiting > 0 ? "\(waiting) waiting" : "All clear")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(waiting > 0 ? Color.orange : .white.opacity(0.9))
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
            StatusDot(needsInput: model.needsInputCount > 0)
            Text(model.needsInputCount > 0
                 ? "\(model.needsInputCount) waiting on you"
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
                              deny: { onResolve(false) }, skip: onSkip)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Text(request.title)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button("Deny", action: deny).buttonStyle(.bordered)
                Button("Approve", action: approve).buttonStyle(.borderedProminent).tint(.orange)
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

private struct SessionRow: View {
    let session: Session
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: session.source.symbol)
                    .frame(width: 22)
                    .foregroundStyle(.white.opacity(0.7))
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
                        Text(session.state.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
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
