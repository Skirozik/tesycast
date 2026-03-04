import Foundation
import Combine

@MainActor
class StreamManager: ObservableObject {

    @Published var isStreaming = false
    @Published var streamURL = "https://tescast.com"
    @Published var errorMessage: String? = nil

    private var pollTimer: Timer?

    static let shared = StreamManager()

    private init() {
        startPolling()
    }

    // MARK: - Broadcast status polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
            let active = defaults?.bool(forKey: "broadcastActive") ?? false
            DispatchQueue.main.async {
                self?.isStreaming = active
            }
        }
    }
}

