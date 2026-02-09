import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: AvatarWindow!
    private var orbView: OrbView!
    private var stateWatcher: StateFileWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create window
        window = AvatarWindow()

        // Create orb view
        orbView = OrbView(frame: NSRect(origin: .zero, size: window.contentView!.bounds.size))
        orbView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(orbView)

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

    @objc private func handleShouldHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.window.orderOut(nil)
        }
    }

    @objc private func handleShouldShow() {
        window.orderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
