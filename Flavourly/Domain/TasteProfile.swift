import Foundation

/// What this cook actually likes, learned from behaviour rather than the setup quiz: what they cook
/// again, how they rate it, what they favourite. Old signals fade (half-life 60 days), low ratings
/// count against a dish's cuisine, tags and main ingredients.
struct TasteProfile: Equatable {
    struct Signal {
        var facts: RecipeFacts
        var cookedCount: Int
        var rating: Int
        var isFavorite: Bool
        var lastCooked: Date?
    }

    /// Feature ("cuisine:indian", "tag:one-pot", "ing:paneer") → affinity, roughly -1…1 after scaling.
    private(set) var weights: [String: Double] = [:]
    /// Human label per feature for the "why" line.
    private(set) var labels: [String: String] = [:]

    var isEmpty: Bool { weights.isEmpty }

    static let halfLifeDays = 60.0

    static func learn(from signals: [Signal], now: Date = .now) -> TasteProfile {
        var profile = TasteProfile()
        for signal in signals {
            let age = signal.lastCooked.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 120
            let decay = pow(0.5, age / halfLifeDays)
            var weight = min(Double(signal.cookedCount), 5) * 0.6 * decay
            if signal.rating > 0 { weight += Double(signal.rating - 3) * 0.8 * max(decay, 0.35) }
            if signal.isFavorite { weight += 1 }
            guard abs(weight) > 0.05 else { continue }
            for (feature, label) in features(of: signal.facts) {
                profile.weights[feature, default: 0] += weight
                profile.labels[feature] = label
            }
        }
        // Scale to about ±1. The floor keeps faded or thin evidence weak instead of stretching it to the
        // top, and a cook with only one or two signals never gets an extreme profile.
        let peak = profile.weights.values.map(abs).max() ?? 0
        let confidence = min(1, Double(signals.filter { $0.cookedCount > 0 || $0.rating > 0 || $0.isFavorite }.count) / 6)
        if peak > 0 {
            let scale = max(peak, 6)
            profile.weights = profile.weights.mapValues { $0 / scale * confidence }.filter { abs($0.value) >= 0.05 }
        }
        return profile
    }

    /// Score boost (−1.5…1.5) and the strongest positive reason, if any.
    func score(_ recipe: RecipeFacts) -> (boost: Double, reason: String?) {
        guard !weights.isEmpty else { return (0, nil) }
        var total = 0.0
        var top: (String, Double)?
        for (feature, _) in Self.features(of: recipe) {
            guard let weight = weights[feature] else { continue }
            total += weight
            if weight > 0.35, weight > (top?.1 ?? 0) { top = (feature, weight) }
        }
        let boost = max(-1.5, min(1.5, total * 0.8))
        let reason = top.flatMap { feature, _ -> String? in
            guard let label = labels[feature] else { return nil }
            if feature.hasPrefix("cuisine:") { return "You often cook \(label)" }
            if feature.hasPrefix("ing:") { return "With \(label), a favourite of yours" }
            return "Like the \(label.lowercased()) dishes you rate highly"
        }
        return (boost, reason)
    }

    /// Cuisine, tags and the three main (non-staple) ingredients.
    static func features(of recipe: RecipeFacts) -> [(String, String)] {
        var out: [(String, String)] = []
        if let cuisine = recipe.cuisine?.trimmingCharacters(in: .whitespaces), !cuisine.isEmpty {
            out.append(("cuisine:" + cuisine.lowercased(), cuisine))
        }
        let ignoredTags: Set<String> = ["ai idea", "imported", "quick", "weeknight"]
        for tag in recipe.tags.prefix(6) where !ignoredTags.contains(tag.lowercased()) {
            out.append(("tag:" + tag.lowercased(), tag))
        }
        var seen = Set<String>()
        for line in recipe.ingredientNames {
            let name = IngredientParser.parse(line).name
            let key = FoodText.key(name)
            guard !key.isEmpty, !GroceryBuilder.staples.contains(key), !commonBases.contains(key), seen.insert(key).inserted else { continue }
            out.append(("ing:" + key, name.lowercased()))
            if seen.count == 3 { break }
        }
        return out
    }

    /// Too common to say anything about taste.
    private static let commonBases: Set<String> = ["oil", "olive oil", "vegetable oil", "onion", "garlic", "water", "sugar", "butter", "flour", "ginger"]
}
