import Foundation

enum MealSlot: String, CaseIterable, Identifiable, Codable, Comparable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var order: Int { MealSlot.allCases.firstIndex(of: self) ?? 0 }
    var symbol: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "leaf.fill"
        }
    }

    static func < (lhs: MealSlot, rhs: MealSlot) -> Bool { lhs.order < rhs.order }

    /// The meal people are most likely deciding on at this hour.
    static func at(hour: Int) -> MealSlot {
        switch hour {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 15..<17: .snack
        default: .dinner
        }
    }

    /// Guess which meals a recipe suits when the source didn't say, so the planner
    /// never puts noodles at breakfast or gravy at lunch.
    static func infer(title: String, tags: [String]) -> Set<MealSlot> {
        let text = FoodText.normalize(([title] + tags).joined(separator: " "))
        func any(_ words: [String]) -> Bool { words.contains { text.contains(FoodText.normalize($0)) } }
        if any(["breakfast", "pancake", "waffle", "porridge", "oatmeal", "overnight oats", "granola", "omelette", "omelet",
                "scrambled", "smoothie", "poha", "upma", "idli", "dosa", "paratha", "muesli", "french toast", "chia pudding", "shakshuka", "cheela", "chilla"]) {
            return [.breakfast]
        }
        if any(["snack", "bites", "chaat", "dip", "energy ball", "popcorn", "makhana", "cookie", "muffin", "bar", "dessert",
                "cake", "brownie", "pudding", "ladoo", "laddu", "halwa", "ice cream", "trail mix"]) {
            return [.snack]
        }
        if any(["salad", "sandwich", "wrap", "soup", "bowl", "toastie", "burger"]) { return [.lunch, .dinner] }
        return [.lunch, .dinner]
    }
}

/// Plain snapshot of a recipe used for ranking (keeps the logic free of Core Data).
struct RecipeFacts: Equatable {
    var id: String
    var title: String
    var ingredientNames: [String]
    var minutes: Int
    var slots: Set<MealSlot>
    var cuisine: String? = nil
    var tags: [String] = []
    var rating: Int = 0
    var isFavorite = false
    var cookedCount = 0
    var lastCooked: Date? = nil
    var protein: Double = 0
    var calories: Double = 0
    var carbs: Double = 0
    var difficulty: Difficulty = .easy
    var equipment: Set<Equipment> = []
}

struct PantrySignal: Equatable {
    let key: String
    let name: String
    let daysLeft: Int?
    /// How much is left, when the cook tracks it (0 = unknown).
    var quantity: Double = 0
    var unit: String = ""

    /// False only when both amounts are known, comparable, and the pantry clearly has too little.
    func covers(_ line: String) -> Bool {
        guard quantity > 0 else { return true }
        let need = IngredientParser.parse(line)
        guard let wanted = need.quantity, wanted > 0 else { return true }
        if let a = Units.toBase(wanted, unit: need.unit), let b = Units.toBase(quantity, unit: unit), Units.family(need.unit) == Units.family(unit) {
            return b >= a * 0.95
        }
        let counts: Set<String> = ["", "piece"]
        if need.unit == unit || (counts.contains(need.unit) && counts.contains(unit)) { return quantity >= wanted * 0.95 }
        return true // g vs cups: can't tell, so trust the cook
    }
}

struct RankContext {
    var profile = FoodProfile()
    var maxMinutes: Int?
    var slot: MealSlot?
    var pantry: [PantrySignal] = []
    var craving = ""
    var cuisines: [String] = []
    var highProtein = false
    /// Cook Now: 0 = only what I have, 2 = OK to buy a couple of things, nil = don't care.
    var maxMissing: Int?
    var exclude: Set<String> = []
    var now = Date()
    /// The cuisine of the cook's country ("Indian"); local dishes rank higher everywhere.
    var localCuisine: String? = RankContext.localCuisine
    /// Set by LocalFood once it knows the country's cuisine.
    nonisolated(unsafe) static var localCuisine: String?
    /// The most demanding level that suits this cook (from the setup quiz); harder recipes rank lower.
    var skillCap: Difficulty? = RankContext.skillCap
    nonisolated(unsafe) static var skillCap: Difficulty?
    /// Automatic plans: also skip recipes that only *might* contain an allergen ("pesto" → nuts?).
    var strictAllergens = false
    var maxCalories: Double?
    var minProtein: Double?
    /// Learned from what this cook makes and rates (set by the app after cooking).
    var taste: TasteProfile = RankContext.taste
    nonisolated(unsafe) static var taste = TasteProfile()
}

struct Ranked: Identifiable {
    let facts: RecipeFacts
    let score: Double
    let reasons: [String]
    let have: [String]
    let missing: [String]
    let useSoon: [String]
    let coverage: Double
    let check: FoodCheckResult
    var id: String { facts.id }
}

enum Recommender {
    private static let stopWords: Set<String> = ["a", "an", "the", "and", "or", "with", "something", "some", "want", "i", "me", "food", "dish", "make", "cook", "for", "to", "of", "in", "tonight", "today"]

    static func rank(_ recipes: [RecipeFacts], _ context: RankContext) -> [Ranked] {
        recipes.compactMap { evaluate($0, context) }.sorted {
            $0.score == $1.score ? $0.facts.title < $1.facts.title : $0.score > $1.score
        }
    }

    /// Nil when a hard rule rejects the recipe (allergen, diet, dislike, time, meal slot, too much to buy).
    static func evaluate(_ recipe: RecipeFacts, _ context: RankContext) -> Ranked? {
        guard !context.exclude.contains(recipe.id) else { return nil }
        let check = FoodRules.check(ingredients: recipe.ingredientNames, profile: context.profile, carbsPerServing: recipe.carbs)
        if check.isBlocked || check.hasDislike { return nil }
        if context.strictAllergens, !check.allergenIssues.isEmpty { return nil }
        if let cap = context.maxCalories, recipe.calories > cap { return nil }
        if let floor = context.minProtein, recipe.calories > 0, recipe.protein < floor { return nil }
        if let limit = context.maxMinutes, recipe.minutes > 0, recipe.minutes > limit { return nil }
        let slots = recipe.slots.isEmpty ? MealSlot.infer(title: recipe.title, tags: recipe.tags) : recipe.slots
        if let slot = context.slot, !slots.contains(slot) { return nil }

        var have: [String] = [], missing: [String] = [], useSoon: [String] = []
        var counted = 0
        for name in recipe.ingredientNames {
            let key = FoodText.key(name)
            guard !key.isEmpty, !GroceryBuilder.staples.contains(key) else { continue }
            counted += 1
            if let stock = context.pantry.first(where: { matches(key, $0.key) }), stock.covers(name) {
                have.append(stock.name)
                if let days = stock.daysLeft, days <= 3 { useSoon.append(stock.name) }
            } else {
                missing.append(GroceryBuilder.displayName(name))
            }
        }
        if let limit = context.maxMissing, missing.count > limit { return nil }

        var score = 0.0
        var reasons: [String] = []
        let coverage = counted == 0 ? 0 : Double(have.count) / Double(counted)
        score += coverage * 3

        let cravingTokens = FoodText.normalize(context.craving).split(separator: " ").map(String.init)
            .filter { !stopWords.contains($0) && $0.count > 1 }
        if !cravingTokens.isEmpty {
            let title = FoodText.normalize(recipe.title)
            let meta = FoodText.normalize((recipe.tags + [recipe.cuisine ?? ""]).joined(separator: " "))
            let ingredients = FoodText.normalize(recipe.ingredientNames.joined(separator: " "))
            var hits: [String] = []
            // What the user asked for right now outweighs pantry and habits.
            for token in cravingTokens {
                let padded = " \(token) "
                if title.contains(padded) { score += 6; hits.append(token) }
                else if meta.contains(padded) { score += 4; hits.append(token) }
                else if ingredients.contains(padded) { score += 3; hits.append(token) }
            }
            if hits.isEmpty { score -= 3 } else { reasons.append("Matches \u{201C}\(hits.joined(separator: " "))\u{201D}") }
        }

        if !useSoon.isEmpty {
            score += min(3, Double(useSoon.count) * 1.5)
            reasons.append("Uses your \(list(useSoon.map { $0.lowercased() }))")
        } else if have.count >= 2 {
            reasons.append("Uses \(have.count) things you have")
        }
        if recipe.rating > 0 {
            score += Double(recipe.rating - 3) * 0.4
            if recipe.rating >= 4 { reasons.append("You rated it \(recipe.rating)★") }
        }
        let learned = context.taste.score(recipe)
        score += learned.boost
        if let reason = learned.reason, recipe.cookedCount == 0, reasons.count < 3 { reasons.insert(reason, at: 0) }
        if recipe.isFavorite { score += 0.8 }
        if let cuisine = recipe.cuisine, context.cuisines.contains(where: { $0.caseInsensitiveCompare(cuisine) == .orderedSame }) {
            score += 0.6
        }
        if let local = context.localCuisine, let cuisine = recipe.cuisine, local.caseInsensitiveCompare(cuisine) == .orderedSame {
            score += 1.2
            reasons.append("\(local) favourite")
        }
        if context.highProtein, recipe.protein >= 25 {
            score += 0.8
            reasons.append("\(Int(recipe.protein)) g protein")
        }
        if let limit = context.maxMinutes, recipe.minutes > 0 {
            score += 0.3 * (1 - Double(recipe.minutes) / Double(max(limit, 1)))
        }
        if recipe.minutes > 0 { reasons.append("Ready in \(recipe.minutes) min") }
        if let last = recipe.lastCooked {
            let days = Calendar.current.dateComponents([.day], from: last, to: context.now).day ?? 99
            if days < 3 { score -= 1.5 } else if days < 7 { score -= 0.7 }
        } else if recipe.cookedCount == 0 {
            score += 0.2
            if reasons.count < 3 { reasons.append("Not tried yet") }
        }
        if check.needsCheck { score -= 0.5 }
        if let cap = context.skillCap, recipe.difficulty > cap {
            score -= Double(recipe.difficulty.rawValue - cap.rawValue)
        } else if context.skillCap == .easy, recipe.difficulty == .easy, reasons.count < 3 {
            reasons.append("Easy to cook")
        }

        return Ranked(facts: recipe, score: score, reasons: Array(reasons.prefix(3)), have: have, missing: missing,
                      useSoon: useSoon, coverage: coverage, check: check)
    }

    static func matches(_ key: String, _ pantryKey: String) -> Bool {
        key == pantryKey || key.hasSuffix(" " + pantryKey) || pantryKey.hasSuffix(" " + key)
    }

    static func list(_ items: [String]) -> String {
        let unique = Array(NSOrderedSet(array: items)) as? [String] ?? items
        switch unique.count {
        case 0: return ""
        case 1: return unique[0]
        case 2: return "\(unique[0]) & \(unique[1])"
        default: return "\(unique[0]), \(unique[1]) & more"
        }
    }
}

// MARK: - Planner

struct PlanSlot: Hashable, Comparable {
    let day: Date
    let slot: MealSlot

    static func < (lhs: PlanSlot, rhs: PlanSlot) -> Bool {
        lhs.day == rhs.day ? lhs.slot < rhs.slot : lhs.day < rhs.day
    }
}

struct PlanPick: Equatable {
    let slot: PlanSlot
    let recipeID: String
    /// Set when this meal is leftovers of another slot (which must cook extra).
    let leftoverOf: PlanSlot?
    let reason: String
}

struct PlannerOptions {
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) when the user is happy to cook.
    var cookDays: Set<Int> = Set(1...7)
    var leftoversForLunch = true
    var weeknightMax: Int? = 30
    var weekendMax: Int? = 60
    /// Daily targets: when set, each day's picks are steered towards them (only recipes with known nutrition count).
    var dailyCalories: Double?
    var dailyProtein: Double?
}

enum Planner {
    /// Fills only the empty slots it is given. Existing (and locked) meals are never touched,
    /// they are only used to avoid repeats and to create next-day leftovers.
    static func fill(
        empty: [PlanSlot],
        existing: [PlanSlot: String],
        recipes: [RecipeFacts],
        base: RankContext,
        options: PlannerOptions,
        calendar: Calendar = .current
    ) -> [PlanPick] {
        var used: [String: Int] = [:]
        for id in existing.values { used[id, default: 0] += 1 }
        var dinners: [Date: (PlanSlot, String)] = [:]
        for (slot, id) in existing where slot.slot == .dinner { dinners[calendar.startOfDay(for: slot.day)] = (slot, id) }
        var picks: [PlanPick] = []
        let titles = Dictionary(recipes.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        for slot in empty.sorted() {
            let day = calendar.startOfDay(for: slot.day)
            let weekday = calendar.component(.weekday, from: day)
            let isCookDay = options.cookDays.contains(weekday)

            if slot.slot == .lunch, options.leftoversForLunch,
               let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
               let source = dinners[yesterday] {
                let title = titles[source.1] ?? "dinner"
                picks.append(PlanPick(slot: slot, recipeID: source.1, leftoverOf: source.0,
                                      reason: "Leftovers of \(title) from \(formatter.string(from: yesterday))"))
                continue
            }

            var context = base
            context.slot = slot.slot
            let isWeekend = weekday == 1 || weekday == 7
            let limit = isWeekend ? options.weekendMax : options.weeknightMax
            context.maxMinutes = isCookDay ? limit : min(limit ?? 15, 15)
            // Breakfast can repeat twice a week; everything else stays varied.
            context.exclude = Set(used.filter { $0.value >= (slot.slot == .breakfast ? 2 : 1) }.keys)

            var ranked = Recommender.rank(recipes, context)
            if ranked.isEmpty {
                // Small cookbook: allow a repeat, but never the same dish on the day before or after.
                let neighbours = [-1, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
                context.exclude = Set(neighbours.compactMap { dinners[$0]?.1 })
                    .union(existing.filter { neighbours.contains(calendar.startOfDay(for: $0.key.day)) }.values)
                ranked = Recommender.rank(recipes, context)
            }
            var chosen = ranked.first
            var balanceNote: String?
            if let target = options.dailyCalories, target > 0, ranked.count > 1 {
                // Share of the day this meal should carry; pick among the top few the one that lands closest.
                let share: Double = [.breakfast: 0.25, .lunch: 0.35, .dinner: 0.35, .snack: 0.1][slot.slot] ?? 0.3
                let slotCalories = target * share
                let slotProtein = (options.dailyProtein ?? 0) * share
                let top = ranked.prefix(8)
                let balanced = top.max { a, b in balanceScore(a, slotCalories, slotProtein) < balanceScore(b, slotCalories, slotProtein) }
                if let balanced, balanced.id != ranked.first?.id, balanced.facts.calories > 0 {
                    chosen = balanced
                    balanceNote = "Keeps the day near \(Int(target)) kcal"
                }
            }
            guard let best = chosen else { continue }
            used[best.id, default: 0] += 1
            if slot.slot == .dinner { dinners[day] = (slot, best.id) }
            let why = ([balanceNote].compactMap { $0 } + best.reasons).prefix(3).joined(separator: " · ").nilIfEmpty ?? "Fits your rules"
            picks.append(PlanPick(slot: slot, recipeID: best.id, leftoverOf: nil,
                                  reason: isCookDay ? why : "Quick one for a no-cook day · " + why))
        }
        return picks
    }

    /// Ranking score minus how far the recipe lands from this meal's share of the day's targets.
    /// Recipes with unknown nutrition keep their score (they can't be steered, but aren't punished).
    static func balanceScore(_ ranked: Ranked, _ calories: Double, _ protein: Double) -> Double {
        guard ranked.facts.calories > 0, calories > 0 else { return ranked.score - 0.5 }
        var score = ranked.score - abs(ranked.facts.calories - calories) / calories * 2
        if protein > 0 { score -= max(0, protein - ranked.facts.protein) / protein }
        return score
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
