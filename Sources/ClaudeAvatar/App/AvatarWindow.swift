import AppKit

final class AvatarWindow: NSWindow {

    init() {
        let size: CGFloat = 540
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
        isMovableByWindowBackground = true
        hasShadow = false
        ignoresMouseEvents = false
    }
}
