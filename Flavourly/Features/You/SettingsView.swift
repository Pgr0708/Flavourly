import CoreData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.openURL) private var openURL
    @StateObject private var pro = ProViewModel()
    @State private var notificationsAllowed = true
    @State private var confirmErase = false
    @State private var confirmReplay = false
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section("Kitchen") {
                Picker("Units", selection: Binding(get: { settings.unitSystem }, set: { settings.unitSystem = $0; Haptics.select() })) {
                    ForEach(UnitSystem.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                Picker("Oven temperature", selection: $settings.usesFahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                Stepper("Default servings: \(settings.defaultServings)", value: $settings.defaultServings, in: 1...20)
                Toggle("Keep screen on while cooking", isOn: $settings.keepScreenOn)
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    .onChange(of: settings.hapticsEnabled) { _, on in if on { Haptics.success() } }
            }

            Section {
                if !notificationsAllowed {
                    Button {
                        Task {
                            if await NotificationService.shared.requestAuthorization() {
                                notificationsAllowed = true
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    } label: {
                        Label("Turn on notifications", systemImage: "bell.badge.fill")
                    }
                }
                Toggle("Cooking timers", isOn: $settings.notifyTimers)
                Toggle("Meal plan reminders", isOn: $settings.notifyPlan)
                if settings.notifyPlan {
                    Picker("Evening reminder", selection: $settings.planReminderHour) {
                        ForEach(17...22, id: \.self) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00")
                                .tag(hour)
                        }
                    }
                }
                Toggle("Use-soon pantry alerts", isOn: $settings.notifyPantry)
                Toggle("Weekly grocery reminder", isOn: $settings.notifyGrocery)
                Toggle("Cookbook ideas on Sundays", isOn: $settings.notifyCookbook)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Reminders are scheduled on your iPhone from your plan and pantry — nothing is sent to a server.")
            }

            Section("Apple Health") {
                NavigationLink(value: Route.healthConnect) {
                    LabeledContent("Apple Health", value: HealthService.shared.isConnected ? "Connected" : "Off")
                }
            }

            Section("Premium") {
                if settings.isPremium {
                    Label("Premium is active", systemImage: "crown.fill").foregroundStyle(Theme.premiumDeep)
                } else {
                    Button { showPaywall = true } label: { Label("See Premium", systemImage: "crown") }
                }
                Button("Restore purchases") {
                    pro.restorePurchases {
                        settings.isPremium = true
                        DropsManager.showSuccess(title: "Purchases restored")
                    }
                }
            }

            Section {
                ShareLink(item: RecipeExport(), preview: SharePreview("Flavourly recipes", image: Image(systemName: "book.fill"))) {
                    Label("Export my recipes", systemImage: "square.and.arrow.up")
                }
                Button { confirmReplay = true } label: { Label("Redo the setup quiz", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) { confirmErase = true } label: { Label("Erase all my data", systemImage: "trash") }
            } header: {
                Text("Your data")
            } footer: {
                Text("No account: recipes, plans and lists stay on this iPhone and your iCloud. Erasing also deletes the anonymous usage record on our server.")
            }

            Section("About") {
                LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                Button("Privacy policy") { if let url = URL(string: AppInfo.privacyURLString) { openURL(url) } }
                Button("Terms of use") { if let url = URL(string: AppInfo.termsURLString) { openURL(url) } }
            }
        }
        .tint(Theme.green)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .dockSpacing()
        .sheet(isPresented: $showPaywall) { PaywallScreenView().environmentObject(settings) }
        .task { notificationsAllowed = await NotificationService.shared.isAuthorized() }
        .onChange(of: pro.errorMessage) { _, message in
            if let message { DropsManager.showError(title: "Restore failed", subtitle: message) }
        }
        .confirmationDialog("Redo the setup quiz?", isPresented: $confirmReplay, titleVisibility: .visible) {
            Button("Start the quiz") {
                settings.customizationStep = 0
                settings.hasSeenCustomization = false
            }
        } message: {
            Text("Your answers are kept as a starting point. Recipes and plans are not affected.")
        }
        .confirmationDialog("Erase all your data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { erase() }
        } message: {
            Text("Deletes every recipe, plan, list, pantry item, person and log on this iPhone and in iCloud. This can't be undone.")
        }
    }

    private func erase() {
        DropsManager.showLoading(title: "Erasing your data…")
        Kitchen.eraseEverything()
        ResponseCache.shared.removeAll()
        ImageCaching.removeAll()
        URLCache.shared.removeAllCachedResponses()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(AppStorageKeys.editorDraftPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Task {
            await APIClient.shared.eraseRemoteData()
            Haptics.destructive()
            DropsManager.showSuccess(title: "All data erased")
        }
    }
}

/// Every saved recipe as JSON, built only when the user actually shares it.
struct RecipeExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { _ in
            try await MainActor.run {
                let recipes = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "isSaved == YES"),
                                                           sort: [NSSortDescriptor(key: "title", ascending: true)])
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(recipes.map { $0.draft() })
            }
        }
        .suggestedFileName("Flavourly recipes.json")
    }
}
