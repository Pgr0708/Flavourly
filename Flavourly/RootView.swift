import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        switch settings.currentFlow {
        case .onboarding:
            OnBoardingScreenView()
        case .customization:
            CustomizationScreenView()
        case .paywall:
            PaywallScreenView()
        case .home:
            ContentView()
        }
    }
}
