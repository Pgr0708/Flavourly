//
//  AppRoot.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI

enum AppFlow {
    case splash
    case language
    case onboarding
    case paywall
    case notification
    case customization
    case home
}

struct RootView: View {
    @EnvironmentObject private var settings: SettingsManager
    
    var currentFlow: AppFlow {
        if !settings.hasSeenLanguage {
            return .language
//        } else if !settings.hasSeenOnboarding {
//            return .onboarding
//        } else if !settings.hasSeenPaywall {
//            return .paywall
//        } else if !settings.hasSeenNotificationPrompt {
//            return .notification
//        } else if !settings.hasSeenCustomization {
//            return .customization
        } else {
            return .home
        }
    }
    
//    var currentFlow: AppFlow {
//
//        // Phase 1: Language + Onboarding
//        if !settings.hasSeenOnboarding {
//            return .language
//        }
//
//        // Phase 2: Paywall + Notification
//        if !settings.hasSeenNotificationPrompt {
//            return .paywall
//        }
//
//        // Phase 3: Customization
//        if !settings.hasSeenCustomization {
//            return .customization
//        }
//
//        return .home
//    }
    
    var body: some View {
        switch currentFlow {
        case .language:
            LanguageScreenView()
            
        case .onboarding:
            OnBoardingScreenView()
            
        case .paywall:
            PaywallScreenView()
            
        case .notification:
            NotificationScreenView()
            
        case .customization:
            CustomizationScreenView()
            
        case .home:
            ContentView()
            
        default:
            SplashScreenView()
        }
    }

}
