//
//  AppStorageKeys.swift
//  Flavourly
//

import Foundation

enum AppStorageKeys {
    static let hasSeenOnboarding           = "hasSeenOnboarding"
    static let onboardingPage              = "onboardingPage"
    static let userName                    = "userName"
    static let languageCode                = "languageCode"
    static let isDarkMode                  = "isDarkMode"

    static let hasSeenLanguage             = "hasSeenLanguage"
    static let hasSeenPaywall              = "hasSeenPaywall"

    // MARK: Notifications
    static let hasSeenNotificationPrompt   = "hasSeenNotificationPrompt"
    static let notificationsEnabled        = "notificationsEnabled"
    static let notifyTimers                = "notifyTimers"
    static let notifyPlan                  = "notifyPlan"
    static let notifyPantry                = "notifyPantry"
    static let notifyGrocery               = "notifyGrocery"
    static let notifyCookbook              = "notifyCookbook"
    static let planReminderHour            = "planReminderHour"

    // MARK: Customization
    static let hasSeenCustomization        = "hasSeenCustomization"
    static let customizationPreferences    = "customizationPreferences"
    static let customizationStep           = "customizationStep"
    static let selectedAccentColor         = "selectedAccentColor"
    static let selectedTheme               = "selectedTheme"
    static let isPremium                   = "isPremium"

    // MARK: Kitchen
    static let hasSeededKitchen            = "hasSeededKitchen"
    static let unitSystem                  = "unitSystem"
    static let temperatureUnit             = "temperatureUnit"
    static let defaultServings             = "defaultServings"
    static let keepScreenOn                = "keepScreenOn"
    static let hapticsEnabled              = "hapticsEnabled"
    static let healthSyncEnabled           = "healthSyncEnabled"
    static let usageLedger                 = "usageLedger"
    static let pendingShares               = "pendingShares"
    /// Prefix for unsaved editor drafts ("editorDraft.new" or "editorDraft.<recipe key>").
    static let editorDraftPrefix           = "editorDraft."
}
