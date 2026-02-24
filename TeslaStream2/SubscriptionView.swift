import SwiftUI

struct SubscriptionView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("Choose Your Plan")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Stream your iPhone to your Tesla\nfrom anywhere in the car")
                    .font(.body)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                Spacer()
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Monthly")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("$4.99 / month")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Yearly")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("$39.99 / year")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                        Spacer()
                        Text("Save 33%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white, lineWidth: 2)
                    )
                }
                Spacer()
                NavigationLink(destination: HomeView()) {
                    Text("Start 7-Day Free Trial")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                Button("Restore Purchases") {
                }
                .foregroundStyle(.gray)
                .font(.footnote)
                Spacer()
                    .frame(height: 20)
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
