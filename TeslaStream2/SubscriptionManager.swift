import Foundation
import StoreKit
import Observation

@MainActor
@Observable
class SubscriptionManager {

    static let shared = SubscriptionManager()

    var isSubscribed = false
    var products: [Product] = []
    var isPurchasing = false
    var errorMessage: String? = nil

    let monthlyID = "com.simeon.TeslaStream2.monthly"
    let yearlyID  = "com.simeon.TeslaStream2.yearly"

    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = listenForTransactionUpdates()
        Task { await loadProductsAndStatus() }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Setup

    func loadProductsAndStatus() async {
        await loadProducts()
        await updateSubscriptionStatus()
    }

    private func loadProducts() async {
        do {
            let fetched = try await Product.products(for: [monthlyID, yearlyID])
            // Monthly first, yearly second
            products = fetched.sorted { $0.id == monthlyID && $1.id == yearlyID }
        } catch {
            errorMessage = "Could not load plans: \(error.localizedDescription)"
        }
    }

    // MARK: - Status

    func updateSubscriptionStatus() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productType == .autoRenewable {
                hasActive = true
            }
        }
        isSubscribed = hasActive
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return }
                await transaction.finish()
                await updateSubscriptionStatus()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await AppStore.sync()
        await updateSubscriptionStatus()
    }

    // MARK: - Background updates

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                }
            }
        }
    }
}
