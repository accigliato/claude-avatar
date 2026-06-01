import AppKit

final class AvatarWindow: NSWindow {

    static let avatarSize: CGFloat = 300
    /// Margin from the screen edge used when snapping to the default corner.
    private static let edgeMargin: CGFloat = 20
    /// If less than this fraction of the window is visible on any screen,
    /// we treat it as "lost" and snap it back to the default corner.
    private static let minVisibleFraction: CGFloat = 0.6

    init() {
        let size = Self.avatarSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = Self.defaultFrame(for: screen, size: size)

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

    /// Default resting position: bottom-right corner of the given screen's
    /// visible area, inset by `edgeMargin`.
    private static func defaultFrame(for screen: NSScreen?, size: CGFloat) -> NSRect {
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screenFrame.maxX - size - edgeMargin,
            y: screenFrame.minY + edgeMargin
        )
        return NSRect(origin: origin, size: NSSize(width: size, height: size))
    }

    /// Keeps the avatar reachable across monitor changes.
    ///
    /// Called whenever the screen configuration changes (monitor plugged in /
    /// unplugged, resolution change). If the window is still mostly visible on
    /// some screen it just gets clamped fully inside that screen's visible area;
    /// otherwise — e.g. it was sitting on a monitor that got disconnected — it
    /// snaps back to the default corner of the main screen so its buttons are
    /// always clickable.
    func ensureVisible() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let f = frame
        let windowArea = f.width * f.height
        guard windowArea > 0 else { return }

        // Find the screen that currently shows the most of the window.
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in screens {
            let inter = screen.visibleFrame.intersection(f)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }

        if let screen = bestScreen, bestArea / windowArea >= Self.minVisibleFraction {
            // Mostly visible — just nudge it fully inside that screen.
            let clamped = Self.clamp(frame: f, into: screen.visibleFrame)
            if clamped != f.origin {
                setFrameOrigin(clamped)
            }
        } else {
            // Lost off-screen (or wedged between screens) — go home.
            let home = Self.defaultFrame(for: NSScreen.main ?? screens.first, size: f.width)
            setFrameOrigin(home.origin)
        }
    }

    /// Clamps a window's origin so the whole frame fits inside `bounds`.
    private static func clamp(frame: NSRect, into bounds: NSRect) -> CGPoint {
        var x = frame.origin.x
        var y = frame.origin.y
        x = min(max(x, bounds.minX), bounds.maxX - frame.width)
        y = min(max(y, bounds.minY), bounds.maxY - frame.height)
        return CGPoint(x: x, y: y)
    }
}

/// A view that only accepts mouse events within a tight hitbox around the avatar body.
/// Placed as an overlay on top of the OrbView.
final class AvatarDragView: NSView {

    /// The body rect in the OrbView's coordinate space (set by OrbView on layout)
    var bodyHitRect: NSRect = .zero {
        didSet {
            if bodyHitRect != oldValue {
                refreshTrackingArea()
            }
        }
    }

    weak var orbView: OrbView?

    private var dragOffset: NSPoint = .zero
    private var hoverTrackingArea: NSTrackingArea?

    private func refreshTrackingArea() {
        if let old = hoverTrackingArea {
            removeTrackingArea(old)
        }
        guard bodyHitRect != .zero else { return }
        let area = NSTrackingArea(
            rect: bodyHitRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        orbView?.showSpeakerIcon()
    }

    override func mouseExited(with event: NSEvent) {
        orbView?.hideSpeakerIcon()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Check speaker icon click first
        if let orbView = orbView, orbView.isSpeakerIconVisible,
           orbView.speakerIconHitRect.contains(loc) {
            orbView.toggleMute()
            return
        }

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
