import AppKit

/// Where the Dynamic Island sits on a screen, derived from NSScreen at runtime.
struct IslandGeometry: Equatable {
    /// The physical cutout, in global screen coordinates (origin bottom-left).
    var cutout: CGRect
    var screenFrame: CGRect
    /// False when no display has a cutout and we float a synthetic pill instead.
    var isPhysical: Bool

    static let fallbackSize = CGSize(width: 120, height: 32)

    static func compute(for screen: NSScreen) -> IslandGeometry {
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = max(right.minX - left.maxX, 0)
            return IslandGeometry(
                cutout: CGRect(x: left.maxX, y: frame.maxY - inset, width: width, height: inset),
                screenFrame: frame, isPhysical: true)
        }
        let size = fallbackSize
        return IslandGeometry(
            cutout: CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                           width: size.width, height: size.height),
            screenFrame: frame, isPhysical: false)
    }

    /// Prefer the display that has a cutout; otherwise the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Fixed canvas the panel occupies; the island morphs inside it.
    static let canvas = CGSize(width: 560, height: 520)

    /// The panel starts at the very top of the screen; the island shape is flush
    /// with that edge so it grows out of the cutout.
    var panelFrame: CGRect {
        CGRect(x: cutout.midX - Self.canvas.width / 2,
               y: screenFrame.maxY - Self.canvas.height,
               width: Self.canvas.width, height: Self.canvas.height)
    }
}
