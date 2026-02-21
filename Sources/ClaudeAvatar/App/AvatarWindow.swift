import AppKit

final class AvatarWindow: NSWindow {

    init() {
        let size: CGFloat = 300
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screenFrame.maxX - size - 20,
            y: screenFrame.minY + 20
        )
        let frame = NSRect(origin: origin, size: NSSize(width: size, height: size))

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Drag handled by AvatarDragView, NOT by window background
        isMovableByWindowBackground = false
        hasShadow = false
        ignoresMouseEvents = false
    }
}

/// A view that only accepts mouse events within a tight hitbox around the avatar body.
/// Placed as an overlay on top of the OrbView.
final class AvatarDragView: NSView {

    /// The body rect in the OrbView's coordinate space (set by OrbView on layout)
    var bodyHitRect: NSRect = .zero

    private var dragOffset: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bodyHitRect.contains(loc) {
            // Start drag — record offset from window origin
            guard window != nil else { return }
            dragOffset = NSPoint(
                x: event.locationInWindow.x,
                y: event.locationInWindow.y
            )
        } else {
            // Pass through — ignore
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        // Only drag if we started inside hitbox
        if dragOffset != .zero {
            let screenLoc = NSEvent.mouseLocation
            let newOrigin = NSPoint(
                x: screenLoc.x - dragOffset.x,
                y: screenLoc.y - dragOffset.y
            )
            win.setFrameOrigin(newOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragOffset = .zero
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only claim hit if within body hitbox, otherwise let clicks pass through to desktop
        let local = convert(point, from: superview)
        if bodyHitRect.contains(local) {
            return self
        }
        return nil
    }
}
