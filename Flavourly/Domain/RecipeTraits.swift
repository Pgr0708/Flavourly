import Foundation

/// How demanding a recipe is, read from the recipe itself (steps, ingredients, time, techniques).
enum Difficulty: Int, CaseIterable, Comparable, Identifiable {
    case easy = 1, medium, hard

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Challenging"
        }
    }

    static func < (lhs: Difficulty, rhs: Difficulty) -> Bool { lhs.rawValue < rhs.rawValue }

    /// From the setup quiz: beginners get easy recipes first; confident cooks aren't limited.
    init?(skill: String?) {
        switch skill {
        case "Just starting": self = .easy
        case "Comfortable with basics": self = .medium
        default: return nil
        }
    }
}

/// What the method needs, read from the steps ("preheat the oven", "air fryer", "3 whistles").
enum Equipment: String, CaseIterable, Identifiable {
    case noCook, stovetop, oven, airFryer, pressureCooker, microwave, slowCooker

    var id: String { rawValue }
    var label: String {
        switch self {
        case .noCook: "No cooking"
        case .stovetop: "Stovetop"
        case .oven: "Oven"
        case .airFryer: "Air fryer"
        case .pressureCooker: "Pressure cooker"
        case .microwave: "Microwave"
        case .slowCooker: "Slow cooker"
        }
    }
}

enum RecipeTraits {
    private static let techniques = ["knead", "proof", "prove the dough", "laminat", "temper the chocolate", "deep fry", "deep-fry",
                                     "caramel", "souffle", "soufflé", "meringue", "ferment", "sous vide", "flambe", "flambé",
                                     "julienne", "debone", "fillet the", "pastry", "choux", "candy thermometer", "emulsif", "roux"]
    private static let markers: [(Equipment, [String])] = [
        (.airFryer, ["air fryer", "air-fryer", "airfryer"]),
        (.pressureCooker, ["pressure cooker", "pressure cook", "instant pot", "whistle"]),
        (.slowCooker, ["slow cooker", "crockpot", "crock pot"]),
        (.microwave, ["microwave"]),
        (.oven, ["oven", "bake", "baking", "roast", "broil", "gratin"]),
        (.stovetop, ["pan", "pot", "skillet", "wok", "saucepan", "kadai", "kadhai", "tawa", "boil", "simmer", "fry", "saute", "sauté",
                     "sear", "stir-fry", "fried", "steam", "poach", "toast", "heat the", "heat oil", "melt", "griddle", "grill"]),
    ]

    /// One compiled pattern per equipment: whole words, with normal endings ("pans", "grilled", "simmering").
    private static let patterns: [(Equipment, NSRegularExpression)] = markers.compactMap { equipment, words in
        let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return (try? NSRegularExpression(pattern: "\\b(\(alternatives))(s|es|d|ed|ing)?\\b")).map { (equipment, $0) }
    }

    static func difficulty(steps: [String], ingredientCount: Int, minutes: Int) -> Difficulty {
        let text = steps.joined(separator: " ").lowercased()
        var points = 0
        if steps.count > 8 { points += 1 }
        if steps.count > 14 { points += 1 }
        if ingredientCount > 10 { points += 1 }
        if ingredientCount > 16 { points += 1 }
        if minutes > 75 { points += 1 }
        points += min(2, techniques.filter { text.contains($0) }.count)
        switch points {
        case ...1: return .easy
        case 2...3: return .medium
        default: return .hard
        }
    }

    /// Everything the steps need. A recipe with steps but no heat at all is "no cooking".
    static func equipment(steps: [String]) -> Set<Equipment> {
        let text = " " + steps.joined(separator: " ").lowercased() + " "
        var found = Set<Equipment>()
        let range = NSRange(text.startIndex..., in: text)
        for (equipment, pattern) in patterns where pattern.firstMatch(in: text, range: range) != nil {
            found.insert(equipment)
        }
        if found.isEmpty, !steps.isEmpty, text.range(of: "\\b(cook|heat|warm)", options: .regularExpression) == nil { found.insert(.noCook) }
        return found
    }
}
