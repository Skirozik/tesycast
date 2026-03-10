import SwiftUI

struct ContentView: View {

    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var isChecking = true
    private let isDebug: Bool = false

    var body: some View {
        NavigationStack {
            if isChecking {
                Color.black.ignoresSafeArea()
            } else {
                HomeView()
            }
        }
        .environment(subscriptionManager)
        .task {
            await subscriptionManager.loadProductsAndStatus()
            isChecking = false
        }
    }
}
