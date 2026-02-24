import ReplayKit
import HaishinKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {

    private let connection = RTMPConnection()
    private lazy var stream: RTMPStream = {
        RTMPStream(connection: connection)
    }()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        connection.connect("rtmp://192.168.1.22/live")
        stream.publish("screen")
    }

    override func broadcastFinished() {
        stream.close()
        connection.close()
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            stream.append(sampleBuffer, track: 0)
        case .audioApp:
            stream.append(sampleBuffer, track: 1)
        case .audioMic:
            break
        @unknown default:
            break
        }
    }
}
