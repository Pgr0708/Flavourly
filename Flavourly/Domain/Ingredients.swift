import Foundation

// MARK: - Units

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric, us
    var id: String { rawValue }
    var label: String { self == .metric ? "Metric" : "US" }
}

enum Units {
    enum Family: Equatable { case mass, volume, other }

    /// Grams or millilitres per unit.
    static let base: [String: (Family, Double)] = [
        "mg": (.mass, 0.001), "g": (.mass, 1), "kg": (.mass, 1000), "oz": (.mass, 28.3495), "lb": (.mass, 453.592),
        "ml": (.volume, 1), "l": (.volume, 1000), "tsp": (.volume, 4.92892), "tbsp": (.volume, 14.7868),
        "cup": (.volume, 240), "fl oz": (.volume, 29.5735)
    ]

    static let aliases: [String: String] = [
        "g": "g", "gram": "g", "grams": "g", "gm": "g", "gms": "g", "gr": "g", "grm": "g",
        "kg": "kg", "kgs": "kg", "kilogram": "kg", "kilograms": "kg", "kilo": "kg", "kilos": "kg", "mg": "mg",
        "ml": "ml", "mls": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "l": "l", "ltr": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
        "tsp": "tsp", "tsps": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
        "tbsp": "tbsp", "tbsps": "tbsp", "tbs": "tbsp", "tbl": "tbsp", "tbls": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
        "cup": "cup", "cups": "cup", "oz": "oz", "ounce": "oz", "ounces": "oz",
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "pinch": "pinch", "pinches": "pinch", "dash": "dash", "dashes": "dash",
        "clove": "clove", "cloves": "clove", "piece": "piece", "pieces": "piece", "pc": "piece", "pcs": "piece",
        "slice": "slice", "slices": "slice", "can": "can", "cans": "can", "tin": "can", "tins": "can",
        "jar": "jar", "jars": "jar", "packet": "packet", "packets": "packet", "pack": "packet", "packs": "packet",
        "bunch": "bunch", "bunches": "bunch", "sprig": "sprig", "sprigs": "sprig", "handful": "handful", "handfuls": "handful",
        "stick": "stick", "sticks": "stick", "head": "head", "heads": "head", "inch": "inch", "inches": "inch", "cm": "cm",
        "drop": "drop", "drops": "drop", "cube": "cube", "cubes": "cube", "sheet": "sheet", "sheets": "sheet",
        "stalk": "stalk", "stalks": "stalk", "fillet": "fillet", "fillets": "fillet", "bottle": "bottle", "bottles": "bottle",
        "block": "block", "blocks": "block", "bag": "bag", "bags": "bag", "box": "box", "scoop": "scoop", "scoops": "scoop"
    ]

    static func family(_ unit: String) -> Family { base[unit]?.0 ?? .other }

    static func toBase(_ quantity: Double, unit: String) -> Double? {
        base[unit].map { quantity * $0.1 }
    }

    static func canonical(_ token: String) -> String? {
        let cleaned = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()"))
        return aliases[cleaned]
    }

    static func display(_ unit: String, quantity: Double?) -> String {
        guard !unit.isEmpty else { return "" }
        let plural = (quantity ?? 1) > 1.0001
        switch unit {
        case "cup": return plural ? "cups" : "cup"
        case "g", "kg", "mg", "ml", "l", "tsp", "tbsp", "oz", "lb", "fl oz", "cm": return unit
        case "pinch", "dash", "bunch", "box": return plural ? unit + "es" : unit
        case "inch": return plural ? "inches" : "inch"
        default: return plural ? unit + "s" : unit
        }
    }
}

// MARK: - Parsing

struct ParsedIngredient: Equatable {
    var quantity: Double?
    var quantityMax: Double?
    var unit: String = ""
    var name: String
    var note: String?
    var original: String
    var isOptional = false
    var isVague = false

    /// 1 = sure, 0.5 = "please check" (vague amount), 0.3 = couldn't find a name.
    var confidence: Double { name.isEmpty ? 0.3 : (isVague ? 0.5 : 1) }
}

enum IngredientParser {
    private static let fractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4", "⅕": "1/5",
        "⅙": "1/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
    ]
    private static let vague = ["to taste", "as needed", "as required", "a little", "a bit of", "some ", "a few", "few ",
                                "splash", "drizzle", "a handful", "handful of", "as per taste", "if needed"]

    static func parse(_ raw: String) -> ParsedIngredient {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = line.first, "•-*–—▢□◦·●▪︎✓".contains(first) {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        let original = line
        var expanded = ""
        for character in line {
            if let fraction = fractions[character] {
                if expanded.last?.isNumber == true { expanded += " " }
                expanded += fraction
            } else {
                expanded.append(character)
            }
        }
        // Split glued amounts like "200g" or "1.5kg" into "200 g".
        expanded = expanded.replacingOccurrences(of: "(\\d)([a-zA-Z])", with: "$1 $2", options: .regularExpression)
        expanded = expanded.replacingOccurrences(of: "(\\d)\\s*[-–—]\\s*(\\d)", with: "$1-$2", options: .regularExpression)

        var tokens = expanded.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var result = ParsedIngredient(name: "", original: original)

        // Quantity
        if let first = tokens.first {
            if first.contains("-"), case let parts = first.split(separator: "-"), parts.count == 2,
               let low = number(String(parts[0])), let high = number(String(parts[1])) {
                result.quantity = low
                result.quantityMax = high
                tokens.removeFirst()
            } else if let value = number(first) {
                result.quantity = value
                tokens.removeFirst()
                if let next = tokens.first, next.contains("/"), let fraction = number(next) {
                    result.quantity = value + fraction
                    tokens.removeFirst()
                }
                if tokens.count >= 2, ["to", "or", "-", "–"].contains(tokens[0].lowercased()), let high = number(tokens[1]) {
                    result.quantityMax = high
                    tokens.removeFirst(2)
                }
            } else if ["a", "an", "one"].contains(first.lowercased()), tokens.count > 1, Units.canonical(tokens[1]) != nil {
                result.quantity = 1
                tokens.removeFirst()
            }
        }

        // Parenthetical right after the amount, e.g. "1 (400 g) can chickpeas".
        var notes: [String] = []
        if let first = tokens.first, first.hasPrefix("(") {
            var inner: [String] = []
            while let token = tokens.first {
                inner.append(token)
                tokens.removeFirst()
                if token.hasSuffix(")") { break }
            }
            notes.append(inner.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "()")))
        }

        // Unit
        if tokens.count >= 2, ["fl", "fluid"].contains(tokens[0].lowercased()), ["oz", "ounce", "ounces"].contains(tokens[1].lowercased()) {
            result.unit = "fl oz"
            tokens.removeFirst(2)
        } else if let first = tokens.first, let unit = Units.canonical(first), !(unit == "l" && first.count == 1 && result.quantity == nil) {
            result.unit = unit
            tokens.removeFirst()
        }
        if tokens.first?.lowercased() == "of" { tokens.removeFirst() }

        // Name, notes, optional flag
        var rest = tokens.joined(separator: " ")
        if let range = rest.range(of: "(optional)", options: .caseInsensitive) {
            result.isOptional = true
            rest.removeSubrange(range)
        }
        if rest.lowercased().contains("optional") { result.isOptional = true }
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let inner = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty, inner.lowercased() != "optional" { notes.append(inner) }
            rest.removeSubrange(open...close)
        }
        let commaParts = rest.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        result.name = (commaParts.first ?? "").trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        if commaParts.count > 1, !commaParts[1].isEmpty { notes.append(commaParts[1]) }
        result.note = notes.isEmpty ? nil : notes.joined(separator: ", ")

        let lower = original.lowercased() + " "
        if result.quantity == nil, vague.contains(where: { lower.contains($0) }) { result.isVague = true }
        if result.name.isEmpty { result.name = original }
        return result
    }

    static func number(_ token: String) -> Double? {
        let text = token.replacingOccurrences(of: ",", with: ".")
        if let value = Double(text), value.isFinite, value >= 0 { return value }
        let parts = text.split(separator: "/")
        if parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom != 0 { return top / bottom }
        return nil
    }
}

// MARK: - Amount formatting

enum Amount {
    /// "320 g", "1 ½ cups", "3–4 cloves", "" when there is no amount.
    static func text(quantity: Double?, max: Double? = nil, unit: String, system: UnitSystem, scale: Double = 1) -> String {
        guard let quantity, quantity > 0 else { return Units.display(unit, quantity: nil) }
        let (value, outUnit) = convert(quantity * scale, unit: unit, to: system)
        var amount = format(value, unit: outUnit, system: system)
        var pluralBasis = value
        if let max, max > quantity {
            // Ranges stay in the same unit as the low end ("3–4 cloves").
            let (high, highUnit) = convert(max * scale, unit: unit, to: system)
            if highUnit == outUnit {
                amount += "–" + format(high, unit: outUnit, system: system)
                pluralBasis = high
            }
        }
        let unitText = Units.display(outUnit, quantity: pluralBasis)
        return unitText.isEmpty ? amount : "\(amount) \(unitText)"
    }

    static func convert(_ quantity: Double, unit: String, to system: UnitSystem) -> (Double, String) {
        guard let (family, factor) = Units.base[unit] else { return (quantity, unit) }
        let base = quantity * factor
        switch (system, family) {
        case (.metric, .mass):
            return base >= 1000 ? (base / 1000, "kg") : (base, "g")
        case (.metric, .volume):
            if unit == "tsp" || unit == "tbsp" { return (quantity, unit) }
            // Metric cooks measure small amounts in spoons (5 ml / 15 ml), not "3.7 ml".
            if base < 14.5 { return (base / 4.92892, "tsp") }
            if base < 29.5 { return (base / 14.7868, "tbsp") }
            return base >= 1000 ? (base / 1000, "l") : (base, "ml")
        case (.us, .mass):
            let ounces = base / 28.3495
            return ounces >= 16 ? (ounces / 16, "lb") : (ounces, "oz")
        case (.us, .volume):
            if unit == "tsp" || unit == "tbsp" { return (quantity, unit) }
            if base >= 59 { return (base / 240, "cup") }
            if base >= 14.7 { return (base / 14.7868, "tbsp") }
            return (base / 4.92892, "tsp")
        default:
            return (quantity, unit)
        }
    }

    static func format(_ value: Double, unit: String, system: UnitSystem) -> String {
        switch unit {
        case "g", "ml":
            if value >= 100 { return String(Int((value / 5).rounded() * 5)) }
            if value >= 10 { return String(Int(value.rounded())) }
            return trimmed(value, places: 1)
        case "kg", "l":
            return trimmed(value, places: 2)
        case "oz", "lb":
            return fraction(value, step: 0.25)
        case "cup":
            return fraction(value, step: 0.125)
        default:
            return fraction(value, step: 0.25)
        }
    }

    static func trimmed(_ value: Double, places: Int) -> String {
        let text = String(format: "%.\(places)f", value)
        guard text.contains(".") else { return text }
        var result = text
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    /// Rounds to kitchen fractions: 1.5 → "1 ½", 0.33 → "⅓".
    static func fraction(_ value: Double, step: Double) -> String {
        let whole = Int(value)
        let remainder = value - Double(whole)
        let thirds: [(Double, String)] = [(1.0 / 3, "⅓"), (2.0 / 3, "⅔")]
        if let third = thirds.first(where: { abs(remainder - $0.0) < 0.04 }) {
            return whole == 0 ? third.1 : "\(whole) \(third.1)"
        }
        let rounded = (remainder / step).rounded() * step
        let glyphs: [Double: String] = [0.125: "⅛", 0.25: "¼", 0.375: "⅜", 0.5: "½", 0.625: "⅝", 0.75: "¾", 0.875: "⅞"]
        if rounded >= 1 { return String(whole + 1) }
        if rounded == 0 { return whole == 0 ? trimmed(value, places: 2) : String(whole) }
        let glyph = glyphs[rounded] ?? trimmed(rounded, places: 2)
        return whole == 0 ? glyph : "\(whole) \(glyph)"
    }
}

// MARK: - Aisles & icons

enum Aisle: String, CaseIterable {
    case produce = "Produce", bakery = "Bakery", meat = "Meat & fish", dairy = "Dairy & eggs", chilled = "Chilled"
    case grains = "Grains, pasta & pulses", tins = "Tins & jars", spices = "Spices & seasoning", oils = "Oils, sauces & sweeteners"
    case baking = "Baking", frozen = "Frozen", drinks = "Drinks", snacks = "Snacks", other = "Other"

    var symbol: String {
        switch self {
        case .produce: "leaf.fill"
        case .bakery: "birthday.cake.fill"
        case .meat: "fish.fill"
        case .dairy: "drop.fill"
        case .chilled: "snowflake"
        case .grains: "takeoutbag.and.cup.and.straw.fill"
        case .tins: "shippingbox.fill"
        case .spices: "sparkles"
        case .oils: "drop.triangle.fill"
        case .baking: "birthday.cake"
        case .frozen: "snowflake.circle.fill"
        case .drinks: "cup.and.saucer.fill"
        case .snacks: "popcorn.fill"
        case .other: "basket.fill"
        }
    }

    private static let table: [(Aisle, [String])] = [
        (.frozen, ["frozen"]),
        (.tins, ["canned", "tinned", "tin of", "can of", "chickpeas can", "coconut milk", "tomato puree", "tomato paste", "passata", "baked beans", "olives", "pickle", "achar", "capers", "jam"]),
        (.meat, ["chicken", "beef", "pork", "lamb", "mutton", "turkey", "bacon", "ham", "sausage", "mince", "keema", "fish", "salmon", "tuna", "cod", "prawn", "shrimp", "crab", "mussel", "squid", "anchovy", "sardine", "mackerel", "steak"]),
        (.dairy, ["milk", "cream", "butter", "cheese", "yoghurt", "yogurt", "curd", "dahi", "ghee", "paneer", "egg", "mozzarella", "parmesan", "feta", "ricotta", "buttermilk", "sour cream", "khoa"]),
        (.chilled, ["tofu", "tempeh", "hummus", "fresh pasta", "pastry", "puff pastry"]),
        (.bakery, ["bread", "bun", "naan", "pita", "bagel", "croissant", "tortilla", "wrap", "roll", "pav", "brioche", "baguette", "sourdough"]),
        (.spices, ["salt", "pepper", "cumin", "jeera", "turmeric", "haldi", "garam masala", "masala", "chilli powder", "chili powder", "paprika", "cinnamon", "cardamom", "clove", "nutmeg", "mustard seed", "fennel seed", "fenugreek", "methi seed", "asafoetida", "hing", "bay leaf", "oregano", "thyme", "rosemary", "chilli flakes", "coriander powder", "stock cube", "bouillon", "seasoning", "saffron", "star anise", "curry powder", "kasuri methi", "ajwain", "chaat masala"]),
        (.oils, ["oil", "vinegar", "soy sauce", "ketchup", "mayonnaise", "mayo", "mustard", "honey", "sugar", "jaggery", "maple", "syrup", "sauce", "sriracha", "tahini", "peanut butter", "pesto"]),
        (.baking, ["flour", "baking powder", "baking soda", "bicarbonate", "yeast", "cocoa", "chocolate chip", "vanilla", "cornstarch", "cornflour", "icing sugar", "maida", "besan", "atta"]),
        (.grains, ["rice", "pasta", "spaghetti", "penne", "fettuccine", "farfalle", "noodle", "macaroni", "oat", "quinoa", "couscous", "semolina", "rava", "sooji", "poha", "lentil", "dal", "daal", "chickpea", "chana", "rajma", "kidney bean", "black bean", "moong", "urad", "masoor", "bulgur", "barley", "vermicelli", "lasagna"]),
        (.drinks, ["juice", "wine", "beer", "coffee", "tea", "soda", "sparkling"]),
        (.snacks, ["chips", "crisps", "biscuit", "cookie", "cracker", "popcorn", "makhana", "chocolate", "nuts", "almond", "cashew", "walnut", "peanut", "raisin", "dates"]),
        (.produce, ["tomato", "onion", "garlic", "potato", "spinach", "palak", "lettuce", "avocado", "lemon", "lime", "apple", "banana", "berry", "strawberry", "blueberry", "raspberry", "orange", "mango", "grape", "basil", "coriander", "cilantro", "mint", "parsley", "dill", "ginger", "chilli", "chili", "cucumber", "carrot", "bell pepper", "capsicum", "mushroom", "broccoli", "cauliflower", "zucchini", "courgette", "eggplant", "aubergine", "brinjal", "cabbage", "kale", "pea", "corn", "green bean", "okra", "bhindi", "pumpkin", "squash", "sweet potato", "beetroot", "radish", "celery", "leek", "scallion", "spring onion", "shallot", "rocket", "arugula", "herb", "curry leaf", "curry leaves", "methi", "fruit", "pomegranate", "pear", "peach", "melon", "watermelon", "pineapple", "kiwi", "asparagus", "sprout"])
    ]

    /// Multi-word phrases that must win over single words ("bell pepper" is produce, "pepper" is a spice).
    private static let overrides: [(String, Aisle)] = overrideTable.map { (FoodText.normalize($0.0), $0.1) }
    private static let overrideTable: [(String, Aisle)] = [
        ("bell pepper", .produce), ("capsicum", .produce), ("green chilli", .produce), ("curry leaves", .produce),
        ("curry leaf", .produce), ("fresh coriander", .produce), ("coriander leaves", .produce), ("spring onion", .produce),
        ("garlic powder", .spices), ("onion powder", .spices), ("ginger powder", .spices), ("chilli powder", .spices),
        ("chili powder", .spices), ("chilli flakes", .spices), ("coriander powder", .spices), ("black pepper", .spices),
        ("peanut butter", .tins), ("almond butter", .tins), ("coconut milk", .tins), ("coconut cream", .tins),
        ("fish sauce", .oils), ("oyster sauce", .oils), ("soy sauce", .oils), ("stock", .tins), ("broth", .tins),
        ("olive oil", .oils), ("sesame oil", .oils), ("coconut oil", .oils), ("vegetable oil", .oils), ("mustard oil", .oils),
        ("sunflower oil", .oils), ("oil", .oils),
        ("cream of tartar", .baking), ("baking powder", .baking), ("ice cream", .frozen)
    ]

    static func classify(_ ingredient: String) -> Aisle {
        let text = FoodText.normalize(ingredient)
        if let hit = overrides.first(where: { text.contains($0.0) }) { return hit.1 }
        for (aisle, words) in table where words.contains(where: { text.contains(FoodText.normalize($0)) }) {
            return aisle
        }
        return .other
    }

    static func sortIndex(_ name: String) -> Int {
        Aisle(rawValue: name).flatMap { Aisle.allCases.firstIndex(of: $0) } ?? Aisle.allCases.count
    }
}

enum IngredientArt {
    /// Emoji illustration for an ingredient, so every row has a picture.
    /// The most specific match wins ("peanut butter" → 🥜, "rice noodles" → 🍜, "coconut milk" → 🥥).
    static func emoji(for name: String) -> String {
        let text = FoodText.normalize(name)
        var best: (length: Int, emoji: String)?
        for (words, emoji) in table {
            for word in words {
                let key = FoodText.normalize(word)
                if key.count > (best?.length ?? 0), text.contains(key) { best = (key.count, emoji) }
            }
        }
        return best?.emoji ?? "🥄"
    }

    /// Real photos we ship for the most common items.
    static func assetName(for name: String) -> String? {
        let text = FoodText.normalize(name)
        let map: [(String, String)] = [
            ("tomato", "IngTomato"), ("spinach", "IngSpinach"), ("avocado", "IngAvocado"), ("egg", "IngEggs"),
            ("yoghurt", "IngYogurt"), ("yogurt", "IngYogurt"), ("curd", "IngYogurt"), ("garlic", "IngGarlic"), ("olive oil", "IngOil")
        ]
        return map.first { text.contains(FoodText.normalize($0.0)) }?.1
    }

    private static let table: [([String], String)] = [
        (["peanut butter"], "🥜"), (["soy sauce", "tamari", "fish sauce"], "🥢"), (["almond milk", "oat milk", "soy milk", "rice milk"], "🥛"),
        (["butternut", "pumpkin", "squash"], "🎃"), (["cornflour", "cornstarch"], "🌾"),
        (["cherry tomato", "tomato"], "🍅"), (["spring onion", "scallion"], "🌱"), (["onion", "shallot"], "🧅"), (["garlic"], "🧄"),
        (["sweet potato"], "🍠"), (["potato", "aloo"], "🥔"), (["carrot"], "🥕"), (["spinach", "lettuce", "kale", "cabbage", "rocket", "arugula", "palak", "methi"], "🥬"),
        (["avocado"], "🥑"), (["cucumber"], "🥒"), (["broccoli"], "🥦"), (["eggplant", "aubergine", "brinjal"], "🍆"),
        (["mushroom"], "🍄"), (["corn"], "🌽"), (["bell pepper", "capsicum"], "🫑"), (["chilli", "chili", "jalapeno"], "🌶️"),
        (["ginger"], "🫚"), (["pea"], "🫛"), (["bean", "rajma", "chickpea", "chana", "lentil", "dal"], "🫘"),
        (["lemon", "lime"], "🍋"), (["apple"], "🍎"), (["banana"], "🍌"), (["strawberry"], "🍓"), (["blueberry", "berry"], "🫐"),
        (["orange"], "🍊"), (["mango"], "🥭"), (["pineapple"], "🍍"), (["grape"], "🍇"), (["peach"], "🍑"), (["watermelon", "melon"], "🍉"),
        (["coconut"], "🥥"), (["olive"], "🫒"), (["basil", "coriander", "cilantro", "mint", "parsley", "dill", "thyme", "rosemary", "herb", "curry leaf"], "🌿"),
        (["egg"], "🥚"), (["milk", "cream", "buttermilk"], "🥛"), (["butter", "ghee"], "🧈"),
        (["cheese", "paneer", "parmesan", "mozzarella", "feta", "ricotta"], "🧀"), (["yoghurt", "yogurt", "curd"], "🥣"),
        (["chicken"], "🍗"), (["beef", "lamb", "mutton", "steak", "pork", "keema", "mince"], "🥩"), (["bacon", "ham"], "🥓"),
        (["shrimp", "prawn"], "🦐"), (["crab", "lobster"], "🦀"), (["squid", "octopus"], "🦑"), (["salmon", "fish", "tuna", "cod"], "🐟"),
        (["bread", "bun", "pav", "baguette"], "🍞"), (["naan", "roti", "tortilla", "wrap", "pita", "paratha", "chapati"], "🫓"),
        (["croissant"], "🥐"), (["rice", "poha"], "🍚"), (["noodle", "ramen"], "🍜"), (["pasta", "spaghetti", "penne", "fettuccine", "farfalle", "macaroni"], "🍝"),
        (["flour", "maida", "atta", "wheat", "oat", "semolina", "rava", "quinoa", "couscous"], "🌾"),
        (["peanut"], "🥜"), (["almond", "cashew", "walnut", "pistachio", "nut"], "🌰"), (["honey"], "🍯"), (["salt"], "🧂"),
        (["sugar", "jaggery"], "🍬"), (["chocolate", "cocoa"], "🍫"), (["oil"], "🫗"), (["water"], "💧"), (["wine"], "🍷"),
        (["coffee"], "☕️"), (["tea"], "🍵"), (["pepper", "cumin", "turmeric", "masala", "paprika", "cinnamon", "spice", "seed"], "🫙"),
        (["tofu"], "⬜️"), (["sauce", "ketchup", "vinegar", "stock", "broth"], "🥫")
    ]
}
