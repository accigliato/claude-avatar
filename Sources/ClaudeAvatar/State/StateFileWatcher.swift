import Foundation

final class StateFileWatcher {

    private let filePath: String
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pollingTimer: DispatchSourceTimer?
    private var lastModification: Date?
    private var onChange: ((AvatarState) -> Void)?

    init(filePath: String = {
        let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return (tmpdir as NSString).appendingPathComponent("claude-avatar-state.json")
    }()) {
        self.filePath = filePath
    }

    func start(onChange: @escaping (AvatarState) -> Void) {
        self.onChange = onChange

        // Create the file if it doesn't exist (owner-only permissions)
        if !FileManager.default.fileExists(atPath: filePath) {
            let initial = "{\"state\":\"idle\",\"timestamp\":\(Int(Date().timeIntervalSince1970))}"
            FileManager.default.createFile(atPath: filePath, contents: initial.data(using: .utf8),
                                           attributes: [.posixPermissions: 0o600])
        }

        // Try DispatchSource first
        if startDispatchSource() {
            return
        }

        // Fallback to polling
        startPolling()
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        pollingTimer?.cancel()
        pollingTimer = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - DispatchSource

    private func startDispatchSource() -> Bool {
        fileDescriptor = open(filePath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readState()
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        dispatchSource = source
        source.resume()

        // Also start a slower polling as backup (DispatchSource can miss events on /tmp)
        startPolling(interval: 1.0)

        return true
    }

    // MARK: - Polling Fallback

    private func startPolling(interval: TimeInterval = 0.5) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.checkForChanges()
        }
        pollingTimer = timer
        timer.resume()
    }

    private func checkForChanges() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let modDate = attrs[.modificationDate] as? Date else { return }

        if lastModification == nil || modDate > lastModification! {
            lastModification = modDate
            readState()
        }
    }

    // MARK: - Read State

    private func readState() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stateString = json["state"] as? String,
              let state = AvatarState(rawValue: stateString) else { return }

        onChange?(state)
    }
}
