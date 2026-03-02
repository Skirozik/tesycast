import Foundation
import Combine

@MainActor
class StreamManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isStreaming = false
    @Published var streamURL = "Finding your IP address..."
    @Published var errorMessage: String? = nil

    // MARK: - Private Properties
    private var localIP: String = "192.168.1.100"
    private var broadcastMonitor: Timer?

    // MARK: - Singleton
    static let shared = StreamManager()

    private init() {
        findLocalIPAddress()
        startBroadcastMonitoring()
    }

    // MARK: - Broadcast State Monitoring
    private func startBroadcastMonitoring() {
        broadcastMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let broadcasting = UserDefaults(suiteName: "group.com.simeon.teslastream")?.bool(forKey: "isBroadcasting") ?? false
            self?.isStreaming = broadcasting
        }
    }

    // MARK: - Find Local IP Address
    func findLocalIPAddress() {
        var address = "Not connected to WiFi"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let interface = ptr!.pointee
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST
                        )
                        address = String(cString: hostname)
                    }
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }

        localIP = address
        streamURL = "rtmp://\(address)/live/stream"

        // Share IP with BroadcastExtension via App Group
        let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
        defaults?.set(address, forKey: "localIP")
    }

}
