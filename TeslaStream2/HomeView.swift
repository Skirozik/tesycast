import SwiftUI

struct HomeView: View {
    @StateObject private var streamManager = StreamManager.shared
    @StateObject private var localServer = LocalServer.shared
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var showStreaming = false
    @State private var showVideo = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            ShootingStarsBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // Header
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TesCast")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                            Text(localServer.isRunning ? "Server ready on :8080" : "Server not running")
                                .font(.subheadline)
                                .foregroundStyle(localServer.isRunning ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                        }
                        Spacer()
                        if streamManager.isStreaming {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: .green, radius: 5)
                                Text("LIVE")
                                    .font(.caption2).fontWeight(.bold)
                                    .foregroundStyle(.green)
                                    .tracking(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                    // Feature cards
                    VStack(spacing: 14) {

                        Button { gate { showStreaming = true } } label: {
                            FeatureCard(
                                icon: "iphone",
                                iconColor: Color(red: 0.2, green: 0.55, blue: 1.0),
                                title: "Mirror Screen",
                                subtitle: "Broadcast your iPhone screen live to your Tesla browser",
                                badge: streamManager.isStreaming ? "Live" : nil,
                                badgeColor: .green
                            )
                        }
                        .buttonStyle(.plain)

                        Button { gate { showVideo = true } } label: {
                            FeatureCard(
                                icon: "play.rectangle.fill",
                                iconColor: Color(red: 0.65, green: 0.3, blue: 1.0),
                                title: "Stream a Video",
                                subtitle: "Upload any video from your Files and play it in Tesla",
                                badge: nil,
                                badgeColor: .clear
                            )
                        }
                        .buttonStyle(.plain)

                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 40)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showStreaming) { StreamingView() }
        .navigationDestination(isPresented: $showVideo) { VideoStreamView() }
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                SubscriptionView()
            }
            .environment(subscriptionManager)
        }
    }

    private func gate(_ action: () -> Void) {
        if subscriptionManager.isSubscribed {
            action()
        } else {
            showPaywall = true
        }
    }
}

// MARK: - Feature Card

struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String?
    let badgeColor: Color

    var body: some View {
        HStack(spacing: 16) {

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(iconColor.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.14))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(badgeColor.opacity(0.3), lineWidth: 1))
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.22))
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
