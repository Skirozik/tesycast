import SwiftUI
import StoreKit

struct SubscriptionView: View {

    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = "com.simeon.TeslaStream2.yearly"

    private var selectedProduct: Product? {
        subscriptionManager.products.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.14), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Decorative glow
            Circle()
                .fill(Color(red: 0.4, green: 0.2, blue: 1.0).opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 80, y: -180)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                // Icon + title
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 90, height: 90)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.white.opacity(0.05), radius: 20)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 8) {
                        Text("TesCast Premium")
                            .font(.title2).fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("Mirror your iPhone screen or stream\nvideos directly to your Tesla browser")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.42))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Plan selector
                if subscriptionManager.products.isEmpty {
                    ProgressView().tint(.white)
                        .frame(height: 120)
                } else {
                    VStack(spacing: 12) {
                        ForEach(subscriptionManager.products, id: \.id) { product in
                            planCard(for: product)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Error
                if let msg = subscriptionManager.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // CTA Button
                Button(action: {
                    guard let product = selectedProduct else { return }
                    Task { await subscriptionManager.purchase(product) }
                }) {
                    Group {
                        if subscriptionManager.isPurchasing {
                            ProgressView().tint(.black)
                        } else {
                            Text("Subscribe")
                        }
                    }
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
                    .shadow(color: Color.white.opacity(0.12), radius: 14, y: 4)
                }
                .disabled(subscriptionManager.isPurchasing || selectedProduct == nil)
                .padding(.horizontal, 28)

                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .foregroundStyle(Color.white.opacity(0.32))
                .font(.footnote)
                .padding(.top, 16)

                Text("Cancel anytime · Auto-renews")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.2))
                    .padding(.top, 8)
                    .padding(.bottom, 44)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .onChange(of: subscriptionManager.isSubscribed) { isSubscribed in
            if isSubscribed { dismiss() }
        }
    }

    // MARK: - Plan Card

    @ViewBuilder
    private func planCard(for product: Product) -> some View {
        let isSelected = product.id == selectedID
        let isYearly   = product.id == subscriptionManager.yearlyID

        Button { selectedID = product.id } label: {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isYearly ? "Yearly" : "Monthly")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(product.displayPrice + (isYearly ? " / year" : " / month"))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer()

                if isYearly {
                    Text("Save 33%")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { SubscriptionView() }
        .environment(SubscriptionManager.shared)
}
