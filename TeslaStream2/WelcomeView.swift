import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                Text("TeslaStream")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Mirror your iPhone\nto your Tesla browser")
                    .font(.title3)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                Spacer()
                NavigationLink(destination: SubscriptionView()) {
                    Text("Get Started")
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
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
}
