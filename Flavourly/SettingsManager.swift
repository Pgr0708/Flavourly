//
//  SettingsManager.swift
//  Flavourly
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

    @AppStorage(AppStorageKeys.languageCode) var languageCode = Languages.english.shortCode.lowercased() { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.isDarkMode) var isDarkMode = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.hasSeenLanguage) var hasSeenLanguage = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.hasSeenPaywall) var hasSeenPaywall = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.hasSeenOnboarding) var hasSeenOnboarding = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.onboardingPage) var onboardingPage = 0 { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.hasSeenNotificationPrompt) var hasSeenNotificationPrompt = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.notificationsEnabled) var notificationsEnabled = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.hasSeenCustomization) var hasSeenCustomization = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.userName) var userName = "" { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.customizationStep) var customizationStep = 0 { didSet { objectWillChange.send() } }

    // MARK: Kitchen settings
    @AppStorage(AppStorageKeys.hasSeededKitchen) var hasSeededKitchen = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.temperatureUnit) var usesFahrenheit = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.defaultServings) var defaultServings = 2 { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.keepScreenOn) var keepScreenOn = true { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.hapticsEnabled) var hapticsEnabled = true { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.healthSyncEnabled) var healthSyncEnabled = false { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.notifyTimers) var notifyTimers = true { didSet { objectWillChange.send() } }
    @AppStorage(AppStorageKeys.notifyPlan) var notifyPlan = true { didSet { objectWillChange.send(); NotificationService.shared.reschedule() } }
    @AppStorage(AppStorageKeys.notifyPantry) var notifyPantry = true { didSet { objectWillChange.send(); NotificationService.shared.reschedule() } }
    @AppStorage(AppStorageKeys.notifyGrocery) var notifyGrocery = true { didSet { objectWillChange.send(); NotificationService.shared.reschedule() } }
    @AppStorage(AppStorageKeys.notifyCookbook) var notifyCookbook = true { didSet { objectWillChange.send(); NotificationService.shared.reschedule() } }
    @AppStorage(AppStorageKeys.planReminderHour) var planReminderHour = 20 { didSet { objectWillChange.send(); NotificationService.shared.reschedule() } }

    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
        set { unitSystemRaw = newValue.rawValue }
    }

    @AppStorage(AppStorageKeys.customizationPreferences)
    private var customizationPreferencesData = Data() { didSet { objectWillChange.send() } }

    var customizationPreferences: CustomizationPreferences {
        get { (try? JSONDecoder().decode(CustomizationPreferences.self, from: customizationPreferencesData)) ?? .init() }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                customizationPreferencesData = data
            }
            RankContext.skillCap = Difficulty(skill: newValue.choices["skill"]?.first)
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

    @AppStorage(AppStorageKeys.selectedAccentColor) var selectedAccentColor = AppAccentColor.teal.rawValue { didSet { objectWillChange.send() } }

    var selectedAppAccentColor: Color {
        AppAccentColor(rawValue: selectedAccentColor)?.color ?? .teal
    }

    @AppStorage(AppStorageKeys.isPremium) var isPremium = false { didSet { objectWillChange.send() } }

    @AppStorage(AppStorageKeys.selectedTheme) var selectedTheme = AppTheme.system.rawValue { didSet { objectWillChange.send() } }

    var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: selectedTheme) {
        case .light: return .light
        case .dark: return .dark
        case .system, .none: return nil
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
