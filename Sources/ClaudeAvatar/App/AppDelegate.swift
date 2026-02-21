import AppKit
import CoreText

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: AvatarWindow!
    private var orbView: OrbView!
    private var dragView: AvatarDragView!
    private var stateWatcher: StateFileWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register SGA font from bundled path or fallback to Resources dir
        registerSGAFont()

        // Create window
        window = AvatarWindow()

        // Create orb view
        orbView = OrbView(frame: NSRect(origin: .zero, size: window.contentView!.bounds.size))
        orbView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(orbView)

        // Create drag overlay (above orb view, handles mouse only in body hitbox)
        dragView = AvatarDragView(frame: NSRect(origin: .zero, size: window.contentView!.bounds.size))
        dragView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(dragView)
        updateDragHitbox()

        // Show window
        window.orderFront(nil)

        // Listen for hide/show notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShouldHide),
            name: .avatarShouldHide,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShouldShow),
            name: .avatarShouldShow,
            object: nil
        )

        // Periodically update drag hitbox (body moves with float)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateDragHitbox()
        }

        // Start file watcher
        stateWatcher = StateFileWatcher()
        stateWatcher.start { [weak self] state in
            DispatchQueue.main.async {
                if state == .idle || state == .listening {
                    // If window is hidden (after goodbye), show it again
                    if self?.window.isVisible == false {
                        self?.window.orderFront(nil)
                        self?.orbView.transitionTo(.idle)
                        // Small delay then transition to the requested state
                        if state != .idle {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self?.orbView.transitionTo(state)
                            }
                        }
                        return
                    }
                }
                self?.orbView.transitionTo(state)
            }
        }
    }

    private func updateDragHitbox() {
        dragView.bodyHitRect = orbView.bodyHitRect
    }

    @objc private func handleShouldHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func handleShouldShow() {
        window.orderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func registerSGAFont() {
        // Try path relative to executable first, then user fonts
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            execURL.appendingPathComponent("sga-font.otf"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Library/Fonts/sga-font.otf")
        ]
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                var errorRef: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
                return
            }
        }
    }
}
