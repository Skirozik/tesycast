import SwiftUI
import Combine

struct StreamingView: View {
    @State private var secondsElapsed = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Text("LIVE")
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
                Text("Streaming to Tesla")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text(formattedTime)
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: {
                }) {
                    Text("Stop Stream")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                Spacer()
                    .frame(height: 20)
            }
        }
        .onReceive(timer) { _ in
            secondsElapsed += 1
        }
        .navigationBarBackButtonHidden(true)
    }

    var formattedTime: String {
        let hours = secondsElapsed / 3600
        let minutes = (secondsElapsed % 3600) / 60
        let seconds = secondsElapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        StreamingView()
    }
}
