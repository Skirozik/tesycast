import Foundation
import Combine

@MainActor
class StreamManager: ObservableObject {

    @Published var isStreaming = false
    @Published var streamURL  = "http://172.20.10.1:8080"
    @Published var mirrorURL  = "http://172.20.10.1:8080/mirror"
    @Published var playerURL  = "http://172.20.10.1:8080/player"
    @Published var errorMessage: String? = nil

    private var pollTimer: Timer?
    private var frameSource: DispatchSourceFileSystemObject?

    static let shared = StreamManager()

    private init() {
        startPolling()
        watchFrameFile()
        startServer()
    }

    // MARK: - Broadcast status polling (drives Live badge in UI)

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
            let active = defaults?.bool(forKey: "broadcastActive") ?? false
            DispatchQueue.main.async {
                self?.isStreaming = active
            }
        }
    }

    // MARK: - Local server lifecycle

    func startServer() {
        LocalServer.shared.start()
    }

    func stopServer() {
        LocalServer.shared.stop()
    }

    // MARK: - Frame file watcher

    private func watchFrameFile() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.simeon.teslastream"
        ) else { return }

        let frameURL = containerURL.appendingPathComponent("latest_frame.jpg")

        // Ensure the file exists so we can open a descriptor
        if !FileManager.default.fileExists(atPath: frameURL.path) {
            FileManager.default.createFile(atPath: frameURL.path, contents: nil)
        }

        let fd = open(frameURL.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[StreamManager] Failed to open frame file for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            guard let data = try? Data(contentsOf: frameURL), !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                LocalServer.shared.pushFrame(data)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        frameSource = source
    }
}
