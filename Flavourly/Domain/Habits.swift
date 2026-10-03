import Foundation

/// How the cook feels right now: picked from the chips on Home, or guessed from their own history.
enum Mood: String, CaseIterable, Codable, Identifiable {
    case tired, lazy, stressed, sad, happy, hungry, cozy, hot, unwell, healthy, energetic, comfort, celebrating, romantic, homesick, adventurous

    var id: String { rawValue }
    var label: String {
        switch self {
        case .tired: "Tired"
        case .lazy: "Lazy"
        case .stressed: "Stressed"
        case .sad: "Low"
        case .happy: "Happy"
        case .hungry: "Very hungry"
        case .cozy: "Rainy day"
        case .hot: "Hot day"
        case .unwell: "Unwell"
        case .healthy: "Healthy"
        case .energetic: "Energetic"
        case .comfort: "Comfort"
        case .celebrating: "Celebrating"
        case .romantic: "Date night"
        case .homesick: "Homesick"
        case .adventurous: "Adventurous"
        }
    }
    var symbol: String {
        switch self {
        case .tired: "moon.zzz.fill"
        case .lazy: "sofa.fill"
        case .stressed: "brain.head.profile"
        case .sad: "cloud.fill"
        case .happy: "face.smiling.fill"
        case .hungry: "fork.knife"
        case .cozy: "cloud.rain.fill"
        case .hot: "sun.max.fill"
        case .unwell: "cross.case.fill"
        case .healthy: "leaf.fill"
        case .energetic: "bolt.fill"
        case .comfort: "heart.fill"
        case .celebrating: "party.popper.fill"
        case .romantic: "wineglass.fill"
        case .homesick: "house.fill"
        case .adventurous: "globe.americas.fill"
        }
    }
}

/// Part of the week and day: habits differ between a weekday evening and a weekend morning.
struct Moment: Hashable, Codable {
    enum Part: String, Codable, CaseIterable { case morning, midday, evening, late }
    let weekend: Bool
    let part: Part

    init(weekend: Bool, part: Part) {
        self.weekend = weekend
        self.part = part
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        weekend = weekday == 1 || weekday == 7
        part = switch hour {
        case 5..<11: .morning
        case 11..<16: .midday
        case 16..<21: .evening
        default: .late
        }
    }

    /// "weekday evenings", "weekend mornings".
    var phrase: String { "\(weekend ? "weekend" : "weekday") \(part.rawValue)s" }
}

/// One thing the cook did. Recorded on the phone (and their own iCloud) only.
struct ActivityRecord {
    enum Kind: String {
        case search, view, cookStart, cookFinish, skip, lock, mood
    }
    var kind: Kind
    var at: Date
    var recipeKey: String? = nil
    var text: String? = nil
    /// cookFinish: minutes it really took. cookStart: the recipe's stated minutes.
    var value: Double = 0
    var mood: Mood? = nil
}

/// What the app learns from activity: when and how long this cook usually cooks, how fast they really are,
/// what they search for, open, skip and lock, and which moods come at which moments. Old activity fades
/// (half-life 45 days); everything is recomputed from the log, so "reset" is just deleting the log.
struct Habits {
    static let halfLifeDays = 45.0

    /// Minutes of the dishes they actually cook at each moment (weighted average).
    private(set) var minutesAt: [Moment: Double] = [:]
    /// How many cooking sessions started at each moment (decayed).
    private(set) var cooksAt: [Moment: Double] = [:]
    /// Real cooking time ÷ the recipe's stated time (1 = as written).
    private(set) var pace: Double = 1
    private(set) var searches: [String: Double] = [:]
    private(set) var opened: [String: Double] = [:]
    private(set) var skipped: [String: Double] = [:]
    private(set) var locked: [String: Double] = [:]
    private(set) var moods: [Moment: [Mood: Double]] = [:]
    /// Most common hour they start cooking dinner (16–23), when known.
    private(set) var usualDinnerHour: Int?
    private(set) var eventCount = 0

    var isEmpty: Bool { eventCount == 0 }

    static func learn(from records: [ActivityRecord], now: Date = .now, calendar: Calendar = .current) -> Habits {
        var habits = Habits()
        habits.eventCount = records.count
        var minuteSums: [Moment: (sum: Double, weight: Double)] = [:]
        var paceSum = 0.0, paceWeight = 0.0
        var dinnerHours: [Int: Double] = [:]
        var started: [String: ActivityRecord] = [:]

        for record in records.sorted(by: { $0.at < $1.at }) {
            let age = max(0, now.timeIntervalSince(record.at) / 86_400)
            let decay = pow(0.5, age / halfLifeDays)
            let moment = Moment(record.at, calendar: calendar)
            switch record.kind {
            case .search:
                for term in terms(record.text) { habits.searches[term, default: 0] += decay }
            case .view:
                if let key = record.recipeKey { habits.opened[key, default: 0] += decay }
            case .skip:
                if let key = record.recipeKey { habits.skipped[key, default: 0] += decay }
            case .lock:
                if let key = record.recipeKey { habits.locked[key, default: 0] += decay }
            case .mood:
                if let mood = record.mood { habits.moods[moment, default: [:]][mood, default: 0] += decay }
            case .cookStart:
                habits.cooksAt[moment, default: 0] += decay
                if record.value > 0 {
                    minuteSums[moment, default: (0, 0)].sum += record.value * decay
                    minuteSums[moment, default: (0, 0)].weight += decay
                }
                let hour = calendar.component(.hour, from: record.at)
                if (16...23).contains(hour) { dinnerHours[hour, default: 0] += decay }
                if let key = record.recipeKey { started[key] = record }
                if let mood = record.mood { habits.moods[moment, default: [:]][mood, default: 0] += decay * 0.5 }
            case .cookFinish:
                // Real time vs stated time, only for plausible sessions (left running overnight doesn't count).
                if let key = record.recipeKey, let start = started[key], start.value > 0, record.value > 0,
                   record.value < start.value * 4, record.at.timeIntervalSince(start.at) < 6 * 3600 {
                    paceSum += min(2, max(0.6, record.value / start.value)) * decay
                    paceWeight += decay
                }
            }
        }
        habits.minutesAt = minuteSums.compactMapValues { $0.weight > 0.3 ? $0.sum / $0.weight : nil }
        if paceWeight > 0.5 { habits.pace = paceSum / paceWeight }
        if let best = dinnerHours.max(by: { $0.value < $1.value }), best.value > 1 { habits.usualDinnerHour = best.key }
        return habits
    }

    /// Words worth learning from a search ("easy paneer curry" → "paneer", "curry").
    static func terms(_ text: String?) -> [String] {
        let stop: Set<String> = ["easy", "quick", "recipe", "recipes", "best", "simple", "with", "and", "how", "make", "the", "for", "homemade"]
        return (text ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }

    /// The cook's typical cooking time at this moment, adjusted to how fast they really are.
    func usualMinutes(at date: Date, calendar: Calendar = .current) -> Int? {
        minutesAt[Moment(date, calendar: calendar)].map { Int(($0 * pace).rounded()) }
    }

    /// The mood this cook usually has at this moment, with how sure we are (0…1). Nil when we don't know.
    func likelyMood(at date: Date, calendar: Calendar = .current) -> (mood: Mood, confidence: Double)? {
        let moment = Moment(date, calendar: calendar)
        if let counts = moods[moment], let best = counts.max(by: { $0.value < $1.value }) {
            let total = counts.values.reduce(0, +)
            if best.value >= 1.5, best.value / total >= 0.5 { return (best.key, min(1, best.value / total)) }
        }
        // No history yet: a late weekday evening usually means a tired cook.
        if !moment.weekend, moment.part == .late { return (.tired, 0.3) }
        return nil
    }

    /// Score change and a "because…" line for a recipe, from habits and the current mood.
    func boost(for recipe: RecipeFacts, mood: Mood?, at date: Date, taste: TasteProfile = TasteProfile(), localCuisine: String? = nil,
               calendar: Calendar = .current) -> (boost: Double, reason: String?) {
        var boost = 0.0
        var reasons: [(Double, String)] = []
        let title = recipe.title.lowercased()
        let haystack = ([title, recipe.cuisine ?? ""] + recipe.tags + recipe.ingredientNames).joined(separator: " ").lowercased()

        // Searches: what they keep looking for.
        if let (term, weight) = searches.filter({ haystack.contains($0.key) }).max(by: { $0.value < $1.value }), weight > 0.4 {
            boost += min(0.8, weight * 0.3)
            reasons.append((weight, "You searched \u{201C}\(term)\u{201D}"))
        }
        // Opened before but never cooked: a gentle nudge.
        if let seen = opened[recipe.id], recipe.cookedCount == 0 { boost += min(0.4, seen * 0.15) }
        // Skipped suggestions fade from the top; locked ones are proven favourites.
        if let skips = skipped[recipe.id] { boost -= min(1.5, skips * 0.5) }
        if let locks = locked[recipe.id], locks > 0.3 {
            boost += min(1, locks * 0.4)
            reasons.append((locks + 1, "You lock it in your plans"))
        }
        // Time: dishes that fit how long they usually cook at this moment.
        if let usual = usualMinutes(at: date, calendar: calendar), recipe.minutes > 0 {
            let real = Double(recipe.minutes) * pace
            if real <= Double(usual) * 1.15 {
                boost += 0.3
                reasons.append((0.5, "Fits your usual \(usual) min on \(Moment(date, calendar: calendar).phrase)"))
            } else if real > Double(usual) * 1.7 {
                boost -= 0.5
            }
        }
        if let mood {
            let (change, reason) = Self.moodFit(recipe, mood: mood, haystack: haystack, taste: taste, localCuisine: localCuisine)
            boost += change
            if let reason, change > 0 { reasons.append((2, reason)) }
        }
        return (boost, reasons.max(by: { $0.0 < $1.0 })?.1)
    }

    private static let comfortWords = ["soup", "stew", "curry", "dal", "khichdi", "pasta", "mac", "pie", "ramen", "noodle", "biryani",
                                       "porridge", "risotto", "casserole", "chili", "pulao", "paratha", "rajma", "chole", "lasagne", "lasagna", "congee"]
    private static let festiveWords = ["festive", "dessert", "special", "biryani", "cake", "roast", "kheer", "halwa", "sweet", "party", "feast"]
    private static let lightWords = ["salad", "healthy", "light", "grilled", "steamed", "vegan", "vegetarian", "bowl", "soup"]
    private static let sweetWords = ["sweet", "dessert", "cake", "kheer", "halwa", "pancake", "chocolate", "ice cream", "pudding", "cookie", "brownie", "laddu", "jalebi"]
    private static let cozyWords = ["soup", "stew", "pakora", "bhajia", "bhaji", "fritter", "ramen", "pho", "curry", "porridge", "chai", "khichdi", "congee", "dal", "broth", "hot pot"]
    private static let coolWords = ["salad", "cold", "raita", "smoothie", "chaas", "lassi", "gazpacho", "sushi", "ceviche", "yogurt", "yoghurt", "poke", "summer", "chilled", "sorbet", "kulfi"]
    private static let gentleWords = ["soup", "khichdi", "congee", "porridge", "broth", "rasam", "dal", "ginger", "rice", "oats", "steamed", "moong"]
    private static let heavyWords = ["fried", "deep-fried", "butter", "cream", "cheese", "biryani", "korma", "makhani", "lasagne", "burger"]
    private static let fillingWords = ["biryani", "burger", "pasta", "thali", "lasagne", "lasagna", "pulao", "paratha", "stew", "rice bowl", "bowl"]
    private static let dateWords = ["steak", "risotto", "pasta", "salmon", "special", "dessert", "roast", "wine", "truffle", "tiramisu"]

    static func moodFit(_ recipe: RecipeFacts, mood: Mood, haystack: String, taste: TasteProfile, localCuisine: String? = nil) -> (Double, String?) {
        let minutes = recipe.minutes
        let has = { (words: [String]) in words.contains(where: haystack.contains) }
        switch mood {
        case .tired:
            if minutes > 0, minutes <= 25 { return (0.9, "Easy for a tired day") }
            return minutes > 45 ? (-0.9, nil) : (0, nil)
        case .lazy:
            if minutes > 0, minutes <= 15, recipe.ingredientNames.count <= 7 { return (1.0, "Minimal effort") }
            if minutes > 0, minutes <= 20 { return (0.5, "Minimal effort") }
            return minutes > 30 ? (-1, nil) : (0, nil)
        case .stressed:
            if has(comfortWords), minutes <= 35 { return (0.9, "Easy comfort") }
            if minutes > 0, minutes <= 25 { return (0.5, "Easy comfort") }
            return minutes > 50 ? (-0.6, nil) : (0, nil)
        case .sad:
            return has(comfortWords) || has(sweetWords) ? (0.8, "Something to lift you up") : (0, nil)
        case .happy:
            return has(festiveWords) || has(sweetWords) || recipe.cookedCount == 0 ? (0.5, "Something fun") : (0, nil)
        case .hungry:
            return recipe.calories >= 600 || has(fillingWords) ? (0.8, "Hearty and filling") : (recipe.calories > 0 && recipe.calories < 300 ? -0.5 : 0, nil)
        case .cozy:
            return has(cozyWords) ? (0.8, "Cozy food for a rainy day") : (has(coolWords) ? -0.4 : 0, nil)
        case .hot:
            if has(coolWords) { return (0.8, "Light and cooling") }
            return has(cozyWords) || has(heavyWords) ? (-0.4, nil) : (0, nil)
        case .unwell:
            if has(gentleWords), !has(heavyWords) { return (1.0, "Gentle on the stomach") }
            return has(heavyWords) || haystack.contains("spicy") ? (-0.8, nil) : (0, nil)
        case .healthy:
            if recipe.calories > 750 { return (-0.7, nil) }
            if (recipe.calories > 0 && recipe.calories <= 500 && recipe.protein >= 18) || has(lightWords) {
                return (0.8, "Light and healthy")
            }
            return (0, nil)
        case .energetic:
            return recipe.protein >= 25 || haystack.contains("high protein") ? (0.8, "Protein-packed") : (0, nil)
        case .comfort:
            return has(comfortWords) ? (0.8, "Comfort food") : (-0.1, nil)
        case .celebrating:
            return has(festiveWords) || minutes >= 50 ? (0.7, "Worth celebrating") : (0, nil)
        case .romantic:
            return has(dateWords) && (minutes == 0 || (25...90).contains(minutes)) ? (0.8, "Date-night dinner") : (0, nil)
        case .homesick:
            guard let localCuisine, let cuisine = recipe.cuisine else { return (0, nil) }
            return cuisine.caseInsensitiveCompare(localCuisine) == .orderedSame ? (0.9, "A taste of home") : (-0.2, nil)
        case .adventurous:
            let familiar = taste.score(recipe).boost > 0.15 || recipe.cookedCount > 0
            return familiar ? (-0.3, nil) : (0.8, "Something new for you")
        }
    }

    /// Top search words, for the "What Flavourly learned" screen and search suggestions.
    func topSearches(_ count: Int = 6) -> [String] {
        searches.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }

    /// Moments ranked by how often they cook then.
    var busiestMoments: [Moment] { cooksAt.sorted { $0.value > $1.value }.map(\.key) }
}
