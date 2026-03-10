import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ZStack {
            ShootingStarsBackground()

            VStack(spacing: 0) {
                Spacer()

                // Logo section
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .shadow(color: Color.white.opacity(0.06), radius: 24)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 10) {
                        Text("TesCast")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                        Text("The Tesla companion\nyou've been waiting for")
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                // Feature list in glass card
                VStack(spacing: 0) {
                    featureRow(
                        icon: "iphone",
                        color: Color(red: 0.2, green: 0.55, blue: 1.0),
                        text: "Mirror your iPhone screen live"
                    )
                    Divider().background(Color.white.opacity(0.07))
                    featureRow(
                        icon: "play.rectangle.fill",
                        color: Color(red: 0.65, green: 0.3, blue: 1.0),
                        text: "Stream videos from your library"
                    )
                    Divider().background(Color.white.opacity(0.07))
                    featureRow(
                        icon: "map.fill",
                        color: Color(red: 0.15, green: 0.78, blue: 0.48),
                        text: "Navigation with police & hazard alerts"
                    )
                }
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                }
                .padding(.horizontal, 24)

                Spacer()

                // CTA
                VStack(spacing: 14) {
                    NavigationLink(destination: SubscriptionView()) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color.white, Color(white: 0.88)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(18)
                            .shadow(color: Color.white.opacity(0.14), radius: 14, y: 4)
                    }
                    Text("Cancel anytime")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.22))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.18))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
}
