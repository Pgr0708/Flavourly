import CoreData
import Foundation
internal import Combine

/// Records what the cook does (searches, opened recipes, cooking sessions, moods, locks, skips) on the phone
/// and in their own iCloud only, and keeps the learned `Habits` + today's mood current for every screen.
@MainActor
final class Personalizer: ObservableObject {
    static let shared = Personalizer()

    @Published private(set) var habits = Habits()
    /// A mood picked on Home; it lasts for the current part of the day.
    @Published private(set) var pickedMood: Mood?
    /// The cook's last searches, newest first (shown under the search field).
    @Published private(set) var recentQueries: [String] = UserDefaults.standard.stringArray(forKey: "recentQueries") ?? []
    @Published var isLearning: Bool {
        didSet {
            UserDefaults.standard.set(isLearning, forKey: Self.learningKey)
            relearn()
        }
    }

    private static let learningKey = "learningEnabled"
    private static let moodKey = "pickedMood"
    private static let keepDays = 180.0
    private var cookingStarted: [String: (at: Date, minutes: Int)] = [:]

    private init() {
        isLearning = UserDefaults.standard.object(forKey: Self.learningKey) as? Bool ?? true
        if let saved = UserDefaults.standard.dictionary(forKey: Self.moodKey),
           let raw = saved["mood"] as? String, let at = saved["at"] as? Double,
           Moment(Date(timeIntervalSince1970: at)) == Moment(.now), Date.now.timeIntervalSince1970 - at < 8 * 3600 {
            pickedMood = Mood(rawValue: raw)
        }
    }

    /// The mood suggestions use: the one picked today, else a confident guess from history.
    var mood: Mood? {
        if let pickedMood { return pickedMood }
        guard isLearning, let guess = habits.likelyMood(at: .now), guess.confidence >= 0.5 else { return nil }
        return guess.mood
    }

    /// The mood the chips pre-select (also low-confidence guesses, shown as a suggestion).
    var suggestedMood: Mood? { pickedMood ?? (isLearning ? habits.likelyMood(at: .now)?.mood : nil) }

    // MARK: Recording

    func record(_ kind: ActivityRecord.Kind, recipe: String? = nil, text: String? = nil, value: Double = 0) {
        guard isLearning else { return }
        let event = ActivityEvent(context: CoreDataManager.shared.context)
        event.uuid = UUID()
        event.kind = kind.rawValue
        event.at = .now
        event.recipeKey = recipe
        event.text = text.map { String($0.prefix(80)) }
        event.value = value
        event.mood = (kind == .mood ? pickedMood : mood)?.rawValue
        CoreDataManager.shared.save()
        scheduleRelearn()
    }

    func pick(_ mood: Mood?) {
        pickedMood = mood
        if let mood {
            UserDefaults.standard.set(["mood": mood.rawValue, "at": Date.now.timeIntervalSince1970], forKey: Self.moodKey)
            record(.mood)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.moodKey)
        }
        RankContext.mood = self.mood
    }

    func startedCooking(_ recipe: Recipe) {
        cookingStarted[recipe.key] = (.now, recipe.minutes)
        record(.cookStart, recipe: recipe.key, value: Double(recipe.minutes))
    }

    /// Called when a cook is saved: the real time it took teaches the cook's pace.
    func finishedCooking(_ recipe: Recipe) {
        guard let start = cookingStarted.removeValue(forKey: recipe.key) else { return }
        let minutes = Date.now.timeIntervalSince(start.at) / 60
        guard minutes >= 2 else { return } // tapped through without cooking
        record(.cookFinish, recipe: recipe.key, value: minutes.rounded())
        // A version another cook nearby made: tell the server it was tried, so good ones rise.
        if let id = recipe.remoteID, id.hasPrefix("variation-") { Task { await Variations.tried(String(id.dropFirst(10))) } }
    }

    /// Search words count once the cook stops typing.
    func searched(_ text: String) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        searchTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            record(.search, text: query)
            remember(query)
        }
    }
    private var searchTask: Task<Void, Never>?

    func remember(_ query: String) {
        guard isLearning else { return }
        recentQueries = Array(([query] + recentQueries.filter { $0.caseInsensitiveCompare(query) != .orderedSame }).prefix(8))
        UserDefaults.standard.set(recentQueries, forKey: "recentQueries")
    }

    // MARK: Learning

    private var relearnTask: Task<Void, Never>?
    private func scheduleRelearn() {
        relearnTask?.cancel()
        relearnTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            relearn()
        }
    }

    /// Recomputes habits from the log (fast: a few thousand rows at most).
    func relearn() {
        let since = Date.now.addingTimeInterval(-Self.keepDays * 86_400)
        let events = isLearning ? CoreDataManager.shared.fetch(ActivityEvent.self, NSPredicate(format: "at >= %@", since as NSDate)) : []
        habits = Habits.learn(from: events.compactMap { event in
            guard let kind = ActivityRecord.Kind(rawValue: event.kind ?? ""), let at = event.at else { return nil }
            return ActivityRecord(kind: kind, at: at, recipeKey: event.recipeKey, text: event.text, value: event.value,
                                  mood: event.mood.flatMap(Mood.init(rawValue:)))
        })
        RankContext.habits = habits
        RankContext.mood = mood
    }

    /// At launch: drop activity older than 6 months, then learn.
    func prepare() {
        let old = CoreDataManager.shared.fetch(ActivityEvent.self, NSPredicate(format: "at < %@", Date.now.addingTimeInterval(-Self.keepDays * 86_400) as NSDate))
        if !old.isEmpty {
            old.forEach { CoreDataManager.shared.context.delete($0) }
            CoreDataManager.shared.save()
        }
        relearn()
    }

    /// "Reset what Flavourly learned": deletes the activity log everywhere (iCloud too).
    func reset() {
        CoreDataManager.shared.fetch(ActivityEvent.self).forEach { CoreDataManager.shared.context.delete($0) }
        recentQueries = []
        UserDefaults.standard.removeObject(forKey: "recentQueries")
        CoreDataManager.shared.save()
        pick(nil)
        relearn()
    }
}
