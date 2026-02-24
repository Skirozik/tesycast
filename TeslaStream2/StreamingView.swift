import SwiftUI
import ReplayKit

struct StreamingView: View {

    @StateObject private var streamManager = StreamManager.shared
    @State private var elapsedTime: Int = 0
    @State private var timer: Timer? = nil
    @State private var isBroadcasting = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {

                Spacer()

                // LIVE indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(isBroadcasting ? Color.red : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(isBroadcasting ? "LIVE" : "READY")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(isBroadcasting ? .red : .gray)
                }

                // Timer
                Text(timeString(elapsedTime))
                    .font(.system(size: 48, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)

                // Stream URL
                Text(streamManager.streamURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                // Broadcast Picker Button
                BroadcastPickerView(isBroadcasting: $isBroadcasting)
                    .frame(width: 60, height: 60)

                Text(isBroadcasting ? "Tap above to stop broadcast" : "Tap above to start broadcasting your screen")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
                    .frame(height: 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            timer?.invalidate()
        }
    }

    func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// This is Apple's official broadcast picker button
struct BroadcastPickerView: UIViewRepresentable {
    @Binding var isBroadcasting: Bool

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = "com.simeon.TeslaStream2.BroadcastExtension"
        picker.showsMicrophoneButton = true
        
        // Force the button to be visible
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.imageView?.tintColor = .white
                button.tintColor = .white
                button.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
                button.layer.cornerRadius = 30
            }
        }
        
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

#Preview {
    NavigationStack {
        StreamingView()
    }
}
