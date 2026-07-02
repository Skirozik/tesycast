import SwiftUI

struct HomeView: View {

    @StateObject private var streamManager = StreamManager.shared

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(streamManager.isStreaming ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(streamManager.isStreaming ? "Streaming" : "Not Streaming")
                        .foregroundStyle(streamManager.isStreaming ? .green : .gray)
                        .font(.subheadline)
                }
                Spacer()
                Text("Open this link in your\nTesla browser:")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(streamManager.streamURL)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                Button(action: {
                    UIPasteboard.general.string = streamManager.streamURL
                }) {
                    Label("Copy Link", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }

                Text("Works over cellular or WiFi — no hotspot needed,\nas long as your Tesla has its own connection.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                Spacer()
                NavigationLink(destination: StreamingView()) {
                    Text("Start Stream ▶")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                Spacer()
                    .frame(height: 20)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("TeslaStream")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            streamManager.syncToAppGroup()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
