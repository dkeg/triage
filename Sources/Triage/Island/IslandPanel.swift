import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats over the menu bar around the cutout.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Only claims mouse events inside the island's current rect so the transparent
/// remainder of the canvas stays click-through.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    /// Active regions relative to the window, origin bottom-left, evaluated live.
    var activeRects: () -> [CGRect] = { [] }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for var r in activeRects() {
            // NSHostingView is flipped (origin top-left); the rects are bottom-left.
            if isFlipped { r.origin.y = bounds.height - r.maxY }
            if r.contains(local) { return super.hitTest(point) }
        }
        return nil
    }
}

