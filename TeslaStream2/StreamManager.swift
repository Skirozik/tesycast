import Foundation
import AVFoundation
import HaishinKit
import Combine

@MainActor
class StreamManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isStreaming = false
    @Published var streamURL = "Finding your IP address..."
    @Published var errorMessage: String? = nil

    // MARK: - Private Properties
    private let connection = RTMPConnection()
    private var stream: RTMPStream?
    private var localIP: String = "192.168.1.100"

    // MARK: - Singleton
    static let shared = StreamManager()

    private init() {
        setupAudioSession()
        findLocalIPAddress()
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
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

    // MARK: - Start Streaming
    func startStreaming() {
        errorMessage = nil

        let rtmpStream = RTMPStream(connection: connection)
        self.stream = rtmpStream

        rtmpStream.attachCamera(
            AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            )
        )

        rtmpStream.attachAudio(
            AVCaptureDevice.default(for: .audio)
        )

        connection.connect("rtmp://\(localIP)/live")
        rtmpStream.publish("stream")

        isStreaming = true
    }

    // MARK: - Stop Streaming
    func stopStreaming() {
        stream?.close()
        connection.close()
        isStreaming = false
    }
}
