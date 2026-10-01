import Foundation

/// Result of checking one field: the cleaned value to use, and a message to show when it's not usable.
struct FieldCheck: Equatable {
    let value: String
    let message: String?
    var isValid: Bool { message == nil }
}

/// Cleans anything a person typed or pasted before it is checked, stored or sent.
enum Sanitize {
    /// Characters that are invisible or reorder text (used to hide or spoof content).
    private static let invisible: Set<UInt32> = [0x200B, 0x2060, 0xFEFF, 0x00AD, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
    private static let tag = try! NSRegularExpression(pattern: #"</?[A-Za-z][^<>]{0,300}>"#)

    /// Unicode-normalised, no control/invisible characters or HTML tags, whitespace collapsed, trimmed.
    /// Keeps line breaks (max one blank line) when `multiline` is true. Never truncates — validators report length.
    static func text(_ raw: String, multiline: Bool = false) -> String {
        var text = raw.precomposedStringWithCanonicalMapping
        text = tag.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if invisible.contains(scalar.value) { continue }
            if scalar == "\n" || scalar == "\r" {
                scalars.append(multiline ? "\n" : " ")
            } else if scalar == "\t" {
                scalars.append(" ")
            } else if scalar.properties.generalCategory == .control {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        text = String(scalars)
        text = text.replacingOccurrences(of: #"[ \x{00A0}]{2,}"#, with: " ", options: .regularExpression)
        if multiline {
            text = text.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "1,5" or " 2.25 " → number. Nil for anything that isn't a plain finite decimal.
    static func number(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, text.range(of: #"^\d{1,7}(\.\d{1,3})?$|^\.\d{1,3}$"#, options: .regularExpression) != nil,
              let value = Double(text), value.isFinite else { return nil }
        return value
    }
}

/// Field rules shared by every screen (and mirrored by the backend's validators).
enum Validate {
    enum Limit {
        static let title = 120, summary = 300, ingredient = 200, step = 2000, ingredients = 100, steps = 60
        static let tag = 30, tags = 20, cuisine = 40, notes = 2000, personName = 40, itemName = 60
        static let link = 2048, pasted = 20_000, pastedMin = 20, craving = 80, customMeal = 60, collection = 40, list = 200
    }

    private static func hasLetter(_ text: String) -> Bool { text.unicodeScalars.contains { CharacterSet.letters.contains($0) } }

    static func required(_ raw: String, field: String, max: Int, min: Int = 1, multiline: Bool = false) -> FieldCheck {
        let value = Sanitize.text(raw, multiline: multiline)
        if value.isEmpty { return FieldCheck(value: value, message: "\(field) is required") }
        if value.count < min { return FieldCheck(value: value, message: "\(field) is too short") }
        if value.count > max { return FieldCheck(value: value, message: "\(field) can be up to \(max.formatted()) characters") }
        if !hasLetter(value) { return FieldCheck(value: value, message: "\(field) needs some letters") }
        return FieldCheck(value: value, message: nil)
    }

    /// Optional text: empty is fine, only the length is checked.
    static func optional(_ raw: String, field: String, max: Int, multiline: Bool = false) -> FieldCheck {
        let value = Sanitize.text(raw, multiline: multiline)
        guard value.count <= max else { return FieldCheck(value: value, message: "\(field) can be up to \(max.formatted()) characters") }
        return FieldCheck(value: value, message: nil)
    }

    static func recipeTitle(_ raw: String) -> FieldCheck {
        let check = required(raw, field: "Recipe name", max: Limit.title, min: 2)
        return check.value.isEmpty ? FieldCheck(value: "", message: "Give your recipe a name") : check
    }

    /// Empty lines are allowed (they're dropped); anything else must name an ingredient.
    static func ingredientLine(_ raw: String) -> FieldCheck {
        let value = Sanitize.text(raw)
        if value.isEmpty { return FieldCheck(value: value, message: nil) }
        if value.count > Limit.ingredient { return FieldCheck(value: value, message: "Keep each ingredient under \(Limit.ingredient) characters") }
        // "200 g" or "a pinch" parse to an amount with no food left over.
        let words = IngredientParser.parse(value).name.lowercased().split(separator: " ").map(String.init)
        let food = words.filter { hasLetter($0) && Units.canonical($0) == nil && !["a", "an", "of"].contains($0) }
        if food.isEmpty {
            return FieldCheck(value: value, message: "Add the ingredient's name, e.g. “2 eggs”")
        }
        return FieldCheck(value: value, message: nil)
    }

    static func stepText(_ raw: String) -> FieldCheck {
        let value = Sanitize.text(raw, multiline: true)
        if value.count > Limit.step { return FieldCheck(value: value, message: "Split this step — steps can be up to \(Limit.step.formatted()) characters") }
        return FieldCheck(value: value, message: nil)
    }

    /// A public web link that's safe to send to the importer.
    static func link(_ raw: String) -> (url: URL?, message: String?) {
        var text = Sanitize.text(raw)
        if text.isEmpty { return (nil, "Paste a link to a recipe, reel or video") }
        if text.count > Limit.link { return (nil, "That link is too long") }
        if let found = text.range(of: #"https?://[^\s<>"]+"#, options: [.regularExpression, .caseInsensitive]) { text = String(text[found]) }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              let url = components.url else {
            return (nil, "That doesn't look like a web link")
        }
        if components.user != nil || components.password != nil { return (nil, "Links with a username or password can't be imported") }
        if let port = components.port, ![80, 443].contains(port) { return (nil, "That link uses an unusual port and can't be imported") }
        if isPrivateHost(host) { return (nil, "Links to private or local addresses can't be imported") }
        return (url, nil)
    }

    static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            switch (parts[0], parts[1]) {
            case (10, _), (127, _), (0, _), (169, 254), (192, 168), (100, 64...127): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        return host.hasPrefix("[") || host.contains(":")   // IPv6 literals are never needed for recipe links
    }

    static func pastedRecipe(_ raw: String) -> FieldCheck {
        let value = Sanitize.text(raw, multiline: true)
        if value.count < Limit.pastedMin { return FieldCheck(value: value, message: "Paste the full recipe — the name, ingredients and steps") }
        if value.count > Limit.pasted { return FieldCheck(value: value, message: "That's very long — paste one recipe at a time (up to 20,000 characters)") }
        if !hasLetter(value) { return FieldCheck(value: value, message: "We couldn't find any words in that text") }
        return FieldCheck(value: value, message: nil)
    }

    static func personName(_ raw: String) -> FieldCheck { required(raw, field: "Name", max: Limit.personName) }

    /// Grocery / pantry item: "2 lemons" is fine, "123" is not.
    static func itemName(_ raw: String) -> FieldCheck {
        let value = Sanitize.text(raw)
        if value.isEmpty { return FieldCheck(value: value, message: "Type an item") }
        if value.count > Limit.itemName + 20 { return FieldCheck(value: value, message: "Keep items under \(Limit.itemName) characters") }
        if !hasLetter(value) { return FieldCheck(value: value, message: "Add what it is, e.g. “2 lemons”") }
        return FieldCheck(value: value, message: nil)
    }

    /// "2 lemons, 500 g paneer" (commas or new lines) → cleaned items, plus the first problem.
    static func items(_ raw: String) -> (items: [String], message: String?) {
        let pieces = raw.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { Sanitize.text($0) }.filter { !$0.isEmpty }
        if pieces.isEmpty { return ([], "Type an item") }
        if pieces.count > 50 { return (Array(pieces.prefix(50)), "Add up to 50 items at a time") }
        for piece in pieces {
            if let message = itemName(piece).message { return (pieces, "“\(piece.prefix(24))”: \(message)") }
        }
        return (pieces, nil)
    }

    /// Optional amount: empty → nil.
    static func quantity(_ raw: String) -> (value: Double?, message: String?) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return (nil, nil) }
        guard let value = Sanitize.number(text) else { return (nil, "Use a number, e.g. 2 or 1.5") }
        if value <= 0 { return (nil, "Use an amount above 0") }
        if value > 100_000 { return (nil, "That amount is too large") }
        return (value, nil)
    }

    /// Optional whole number in a sensible range (calorie and macro targets, logged calories).
    static func integer(_ raw: String, field: String, range: ClosedRange<Int>) -> (value: Int?, message: String?) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return (nil, nil) }
        guard text.allSatisfy(\.isNumber), let value = Int(text) else { return (nil, "\(field): use whole numbers only") }
        guard range.contains(value) else { return (nil, "\(field) should be between \(range.lowerBound.formatted()) and \(range.upperBound.formatted())") }
        return (value, nil)
    }

    /// "mushrooms, olives; coriander" → cleaned items. Reports too many / too long items.
    static func list(_ raw: String, field: String, maxItems: Int = 20, maxLength: Int = 40) -> (items: [String], message: String?) {
        let items = Sanitize.text(raw)
            .replacingOccurrences(of: " and ", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { Sanitize.text(String($0)) }
            .filter { !$0.isEmpty }
        if items.count > maxItems { return (Array(items.prefix(maxItems)), "\(field): up to \(maxItems) items") }
        if let long = items.first(where: { $0.count > maxLength }) {
            return (items, "“\(long.prefix(20))…” is too long — keep each item under \(maxLength) characters")
        }
        if let bad = items.first(where: { !hasLetter($0) }) { return (items, "“\(bad)” isn't a food") }
        return (items, nil)
    }

    static func collectionName(_ raw: String) -> FieldCheck { required(raw, field: "Collection name", max: Limit.collection) }

    /// Daily targets people type in Preferences and Household.
    enum Target {
        static let calories = 800...6000, protein = 10...400, carbs = 20...800, fat = 10...300
    }

    /// Whole-recipe check before saving; returns the first problem to show.
    static func recipe(_ draft: RecipeDraftFields) -> String? {
        if let message = recipeTitle(draft.title).message { return message }
        let lines = draft.ingredients.filter { !Sanitize.text($0).isEmpty }
        if lines.isEmpty { return "Add at least one ingredient" }
        if lines.count > Limit.ingredients { return "Recipes can have up to \(Limit.ingredients) ingredients" }
        if let message = draft.ingredients.lazy.compactMap({ ingredientLine($0).message }).first { return message }
        if draft.steps.filter({ !Sanitize.text($0).isEmpty }).count > Limit.steps { return "Recipes can have up to \(Limit.steps) steps" }
        if let message = draft.steps.lazy.compactMap({ stepText($0).message }).first { return message }
        if !(1...40).contains(draft.servings) { return "Servings should be between 1 and 40" }
        if !(0...1440).contains(draft.minutes) { return "Cooking time should be under 24 hours" }
        if let message = optional(draft.summary, field: "Description", max: Limit.summary).message { return message }
        if let message = optional(draft.cuisine, field: "Cuisine", max: Limit.cuisine).message { return message }
        if draft.tags.count > Limit.tags { return "Up to \(Limit.tags) tags" }
        if draft.tags.contains(where: { $0.count > Limit.tag }) { return "Tags can be up to \(Limit.tag) characters" }
        return nil
    }
}

/// The plain fields `Validate.recipe` needs, so it works for the editor, Review Import and tests alike.
struct RecipeDraftFields {
    var title: String
    var summary = ""
    var cuisine = ""
    var servings = 2
    var minutes = 0
    var tags: [String] = []
    var ingredients: [String]
    var steps: [String]
}
