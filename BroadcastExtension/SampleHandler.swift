import ReplayKit
import HaishinKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {

    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    private var retryTimer: Timer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        UserDefaults(suiteName: "group.com.zekeyeagar.teslastream")?.set(true, forKey: "isBroadcasting")
        startStream()
    }

    private func startStream() {
        let defaults = UserDefaults(suiteName: "group.com.zekeyeagar.teslastream")
        let serverIP = defaults?.string(forKey: "serverIP") ?? "YOUR_CLOUD_SERVER_IP"
        let streamKey = defaults?.string(forKey: "streamKey") ?? "stream"
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        self.connection = connection
        self.stream = stream
        connection.connect("rtmp://\(serverIP)/live")
        stream.publish(streamKey)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { [weak self] _ in
            self?.reconnect()
        }
    }

    private func reconnect() {
        retryTimer?.invalidate()
        retryTimer = nil
        stream?.close()
        connection?.close()
        stream = nil
        connection = nil
        startStream()
    }

    override func broadcastFinished() {
        UserDefaults(suiteName: "group.com.zekeyeagar.teslastream")?.set(false, forKey: "isBroadcasting")
        retryTimer?.invalidate()
        retryTimer = nil
        stream?.close()
        connection?.close()
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            stream?.append(sampleBuffer, track: 0)
        case .audioApp:
            stream?.append(sampleBuffer, track: 1)
        case .audioMic:
            break
        @unknown default:
            break
        }
    }
}
