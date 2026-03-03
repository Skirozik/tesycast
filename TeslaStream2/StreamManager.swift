import Foundation
import Combine

@MainActor
class StreamManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isStreaming = false
    @Published var streamURL = "Enter server IP below"
    @Published var serverIP: String {
        didSet {
            UserDefaults.standard.set(serverIP, forKey: "serverIP")
            updateStreamURL()
            syncToAppGroup()
        }
    }

    // MARK: - Private Properties
    private var broadcastMonitor: Timer?
    let streamKey: String

    // MARK: - Singleton
    static let shared = StreamManager()

    private init() {
        // Restore saved server IP
        self.serverIP = UserDefaults.standard.string(forKey: "serverIP") ?? ""

        // Generate or restore persistent stream key
        let key = "userStreamKey"
        if let existing = UserDefaults.standard.string(forKey: key) {
            self.streamKey = existing
        } else {
            let newKey = UUID().uuidString
                .lowercased()
                .replacingOccurrences(of: "-", with: "")
                .prefix(12)
                .description
            UserDefaults.standard.set(newKey, forKey: key)
            self.streamKey = newKey
        }

        updateStreamURL()
        syncToAppGroup()
        startBroadcastMonitoring()
    }

    // MARK: - Update stream URL display
    private func updateStreamURL() {
        if serverIP.isEmpty {
            streamURL = "Enter server IP below"
        } else {
            streamURL = "http://\(serverIP):8888/live/\(streamKey)"
        }
    }

    // MARK: - Share config with BroadcastExtension via App Group
    func syncToAppGroup() {
        let defaults = UserDefaults(suiteName: "group.com.zekeyeagar.teslastream")
        defaults?.set(serverIP, forKey: "serverIP")
        defaults?.set(streamKey, forKey: "streamKey")
    }

    // MARK: - Called from HomeView onAppear (kept for compatibility)
    func findLocalIPAddress() {
        syncToAppGroup()
    }

    // MARK: - Broadcast State Monitoring
    private func startBroadcastMonitoring() {
        broadcastMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let broadcasting = UserDefaults(suiteName: "group.com.zekeyeagar.teslastream")?.bool(forKey: "isBroadcasting") ?? false
            self?.isStreaming = broadcasting
        }
    }
}
