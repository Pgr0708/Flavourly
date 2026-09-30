import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var loadingProgress: CGFloat = 0

    var body: some View {
        if isActive {
            RootView()
        } else {
            GeometryReader { geometry in
                ZStack {
                    Image("SplashPasta")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.15), .black.opacity(0.78)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 3) {
                            Text("Welcome to")
                                .font(.system(size: 17, weight: .medium))
                            Text("Flavourly")
                                .font(.custom("Pacifico-Regular", size: 47))
                                .minimumScaleFactor(0.8)
                            Text("Recipes. Plans. Groceries.\nA Healthier You.")
                                .font(.system(size: 16, weight: .medium))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.top, 4)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.65), radius: 8, y: 3)
                        .padding(.bottom, geometry.size.height * 0.14)

                        Text("Loading delicious things...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.bottom, 10)

                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(width: 150, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.white)
                                    .frame(width: 150 * loadingProgress, height: 4)
                            }
                    }
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(.black)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .task {
                withAnimation(.linear(duration: 2.2)) {
                    loadingProgress = 1
                }
                try? await Task.sleep(for: .seconds(2.3))
                guard !Task.isCancelled else { return }
                isActive = true
            }
        }
    }
}
