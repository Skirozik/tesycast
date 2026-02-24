import ReplayKit
import HaishinKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {

    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    private var retryTimer: Timer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startStream()
    }

    private func startStream() {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        self.connection = connection
        self.stream = stream
        connection.connect("rtmp://192.168.1.22/live")
        stream.publish("screen")
        retryTimer = Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { [weak self] _ in
            self?.reconnect()
        }
    }

    private func reconnect() {
        stream?.close()
        connection?.close()
        stream = nil
        connection = nil
        startStream()
    }

    override func broadcastFinished() {
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
