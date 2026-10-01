import Foundation
import UserNotifications

/// Local reminders: plan, pantry use-soon, grocery, cookbook nudges, cook timers and finished imports.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?
    private let managedPrefix = "flavourly.auto."

    override private init() {
        super.init()
        center.delegate = self
        let open = UNNotificationAction(identifier: "open", title: "Open", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Remind me in 1 hour")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "timer", actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "reminder", actions: [open, snooze], intentIdentifiers: [])
        ])
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        SettingsManager.shared.notificationsEnabled = granted
        if granted { reschedule() }
        return granted
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: Timers & one-offs

    func scheduleTimer(id: String, title: String, body: String, seconds: Int) {
        guard SettingsManager.shared.notifyTimers, seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        content.categoryIdentifier = "timer"
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: "timer.\(id)", content: content, trigger: trigger))
    }

    func cancelTimer(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["timer.\(id)"])
    }

    func notifyImportReady(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Recipe ready to review"
        content.body = "\(title) is waiting in Flavourly — check it and save."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "import.\(UUID().uuidString)", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    // MARK: Scheduled reminders

    /// Debounced: many edits in a row trigger one rebuild.
    func reschedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.rebuild()
        }
    }

    private func rebuild() async {
        guard await isAuthorized() else { return }
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(managedPrefix) })

        let settings = SettingsManager.shared
        let calendar = Calendar.current
        let now = Date.now

        if settings.notifyPlan {
            let meals = Kitchen.meals(from: now, days: 8)
            for meal in meals where meal.mealSlot == .dinner && meal.mealStatus == .planned && !meal.isLeftover {
                guard let day = meal.day, let eve = calendar.date(byAdding: .day, value: -1, to: day),
                      let fire = calendar.date(bySettingHour: settings.planReminderHour, minute: 0, second: 0, of: eve),
                      fire > now else { continue }
                let needsDefrost = meal.recipe?.checkLines.contains { line in
                    ["chicken", "salmon", "fish", "prawn", "beef", "lamb", "mutton", "frozen"].contains { line.lowercased().contains($0) }
                } ?? false
                let minutes = meal.recipe?.minutes ?? 0
                add("plan.\(meal.uuid?.uuidString ?? UUID().uuidString)", title: "Tomorrow: \(meal.title)",
                    body: needsDefrost ? "Take it out of the freezer tonight so it's ready." : (minutes > 0 ? "About \(minutes) min. Everything's on your list." : "Everything's on your list."),
                    at: fire)
            }
            // Evening nudge when tonight's dinner isn't planned yet.
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      let fire = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day), fire > now else { continue }
                let planned = meals.contains { $0.day.map { calendar.isDate($0, inSameDayAs: day) } == true && $0.mealSlot == .dinner }
                if !planned {
                    add("cooknow.\(offset)", title: "What's for dinner?", body: "Tell Flavourly how much time you have and we'll pick something that fits.", at: fire)
                }
            }
        }

        if settings.notifyPantry {
            for item in CoreDataManager.shared.fetch(PantryItem.self) {
                guard let days = item.daysLeft, days >= 0, days <= 1, let expires = item.expiresAt,
                      let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: days == 0 ? now : calendar.startOfDay(for: expires)),
                      fire > now else { continue }
                add("pantry.\(item.uuid?.uuidString ?? item.displayName)", title: "Use \(item.displayName.lowercased()) today",
                    body: "Open Flavourly to see what you can cook with it.", at: fire)
            }
        }

        if settings.notifyGrocery {
            let lines = Kitchen.groceryLines(weekStart: Kitchen.weekStart(), system: settings.unitSystem).filter { !$0.coveredByPantry && !$0.isStaple }
            let checked = Set(Kitchen.groceryState(weekStart: Kitchen.weekStart()).filter { $0.value.isChecked }.keys)
            let open = lines.filter { !checked.contains($0.key) }.count + Kitchen.manualItems().filter { !$0.isChecked }.count
            if open > 0, let saturday = nextWeekday(7, hour: 10, from: now) {
                add("grocery.week", title: "\(open) item\(open == 1 ? "" : "s") on your list",
                    body: "Your grocery list is sorted by aisle and ready to go.", at: saturday)
            }
        }

        if settings.notifyCookbook, let sunday = nextWeekday(1, hour: 18, from: now) {
            let untried = CoreDataManager.shared.count(Recipe.self, NSPredicate(format: "isSaved == YES AND isArchived == NO AND cookedCount == 0"))
            let body = untried > 0
                ? "\(untried) saved recipe\(untried == 1 ? " is" : "s are") waiting to be tried. Plan one into next week?"
                : "Plan next week in a minute — your list builds itself."
            add("cookbook.weekly", title: "Your cookbook", body: body, at: sunday)
        }
    }

    private func nextWeekday(_ weekday: Int, hour: Int, from date: Date) -> Date? {
        Calendar.current.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, weekday: weekday), matchingPolicy: .nextTime)
    }

    private func add(_ id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "reminder"
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: managedPrefix + id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == "snooze" else { return }
        let content = response.notification.request.content
        let copy = UNMutableNotificationContent()
        copy.title = content.title
        copy.body = content.body
        copy.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "snooze.\(UUID().uuidString)", content: copy,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
    }
}
