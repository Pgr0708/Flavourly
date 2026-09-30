import SwiftUI

struct OnBoardingScreenView: View {
    @EnvironmentObject private var settings: SettingsManager
    private var page: Int { settings.onboardingPage }

    private let titles = [
        "Save Recipes\nfrom Anywhere",
        "Plan Your\nPerfect Week",
        "Smart Grocery\nLists",
        "Cook Happier,\nHealthier"
    ]
    private let subtitles = [
        "Import from Instagram, TikTok, YouTube, any website or photo in seconds.",
        "Personalised meal plans for your goals, taste and schedule.",
        "Turn your meal plan into a sorted, smart shopping list.",
        "Step-by-step cooking, nutrition insights and a growing collection you'll love."
    ]
    private let artwork = [
        "OnboardingSave",
        "OnboardingPlan",
        "OnboardingGrocery",
        "OnboardingCook"
    ]
    private let green = Color(hex: "#155634")

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "#FFFDF7")
                    .ignoresSafeArea()

                if page == 2 {
                    LinearGradient(
                        colors: [Color(hex: "#EFF8E9"), Color(hex: "#FFF9EB")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    Image(artwork[page])
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 1.03)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.57)
                        .accessibilityHidden(true)
                } else {
                    Image(artwork[page])
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.72),
                        .init(color: Color(hex: "#FFF9F0").opacity(0.96), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text(titles[page])
                            .font(.system(size: 29, weight: .semibold, design: .serif))
                            .foregroundStyle(green)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitles[page])
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#5D6B63"))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 300)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    Spacer(minLength: 0)

                    if page == 3 {
                        Button("Get Started") {
                            settings.hasSeenOnboarding = true
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#75B85B"), green],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .padding(.horizontal, 30)
                        .padding(.bottom, 20)
                    } else {
                        HStack {
                            Button("Skip") {
                                settings.hasSeenOnboarding = true
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#283A30"))
                            .frame(width: 56, alignment: .leading)

                            Spacer()

                            pageDots

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    settings.onboardingPage += 1
                                }
                            } label: {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 54, height: 54)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: "#75B85B"), green],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        in: Circle()
                                    )
                            }
                            .accessibilityLabel("Next")
                            .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.horizontal, 30)
                    }

                    if page == 3 {
                        pageDots
                    }
                }
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.translation.width < -50 && page < 3 {
                            withAnimation(.easeInOut(duration: 0.25)) { settings.onboardingPage += 1 }
                        } else if value.translation.width > 50 && page > 0 {
                            withAnimation(.easeInOut(duration: 0.25)) { settings.onboardingPage -= 1 }
                        }
                    }
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.light)
        .onAppear {
            settings.onboardingPage = min(max(page, 0), 3)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<4) { index in
                Circle()
                    .fill(index == page ? green : Color(hex: "#D9D7CF"))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of 4")
    }
}
