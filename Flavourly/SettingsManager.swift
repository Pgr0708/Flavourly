//
//  SettingsManager.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI
internal import Combine

enum AppFlow {
    case onboarding
    case customization
    case paywall
    case home
}

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage(AppStorageKeys.languageCode)
    var languageCode = Languages.english.shortCode.lowercased() {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage(AppStorageKeys.isDarkMode)
    var isDarkMode = false
    {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage(AppStorageKeys.hasSeenLanguage)
    var hasSeenLanguage = false
    {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage(AppStorageKeys.hasSeenPaywall)
    var hasSeenPaywall = false
    {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.hasSeenOnboarding)
    var hasSeenOnboarding = false
    {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.onboardingPage)
    var onboardingPage = 0 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.hasSeenNotificationPrompt)
    var hasSeenNotificationPrompt = false
    {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.notificationsEnabled)
    var notificationsEnabled = false
    {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage(AppStorageKeys.hasSeenCustomization)
    var hasSeenCustomization = false
    {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.userName)
    var userName = "" {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.customizationStep)
    var customizationStep = 0 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(AppStorageKeys.customizationPreferences)
    private var customizationPreferencesData = Data() {
        didSet { objectWillChange.send() }
    }

    var customizationPreferences: CustomizationPreferences {
        get { (try? JSONDecoder().decode(CustomizationPreferences.self, from: customizationPreferencesData)) ?? .init() }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                customizationPreferencesData = data
            }
        }
    }

    @AppStorage(AppStorageKeys.homeData)
    private var homeDataStorage = Data() {
        didSet { objectWillChange.send() }
    }

    var homeData: HomeData {
        get { (try? JSONDecoder().decode(HomeData.self, from: homeDataStorage)) ?? .init() }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                homeDataStorage = data
            }
        }
    }

    var displayName: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Chef" : name
    }

    var currentFlow: AppFlow {
        if !hasSeenOnboarding { return .onboarding }
        if !hasSeenCustomization { return .customization }
        if !hasSeenPaywall && !isPremium { return .paywall }
        return .home
    }

    @AppStorage(AppStorageKeys.selectedAccentColor)
    var selectedAccentColor = AppAccentColor.teal.rawValue {
        didSet { objectWillChange.send() }
    }
    
    var selectedAppAccentColor: Color {
        AppAccentColor(rawValue: selectedAccentColor)?.color ?? .teal
    }

    
    @AppStorage(AppStorageKeys.isPremium)
    var isPremium = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("isPDFScanEnabled")
    var isPDFScanEnabled = false {
        didSet { objectWillChange.send() }
    }

     @AppStorage(AppStorageKeys.selectedTheme)
    var selectedTheme = AppTheme.system.rawValue
    {
        didSet { objectWillChange.send() }
    }

    var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: selectedTheme) {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system, .none:
            return nil
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
    
    var id: String { self.rawValue }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
    case teal = "Teal"
    case ocean = "Ocean"
    case purple = "Purple"
    case amber = "Amber"
    case emerald = "Emerald"
    
    var id: String { self.rawValue }
    var localizedName: LocalizedStringKey { LocalizedStringKey(self.rawValue) }
    
    var color: Color {
        switch self {
        case .teal: return Color(hex: "#0A9396")
        case .ocean: return Color(hex: "#0066FF")
        case .purple: return Color(hex: "#8A2BE2")
        case .amber: return Color(hex: "#FFBF00")
        case .emerald: return Color(hex: "#00A86B")
        }
    }
}
