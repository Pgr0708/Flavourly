import Foundation

/// Reads schema.org/Recipe JSON-LD that most recipe websites publish — fast, free and no AI guessing.
enum RecipeWebParser {
    static func parse(html: String, url: URL) -> RecipeDraft? {
        for block in jsonLDBlocks(html) {
            if let object = findRecipe(block) {
                var draft = draft(from: object, url: url)
                if draft.imageURL == nil { draft.imageURL = meta(html, "og:image") }
                return draft
            }
        }
        return nil
    }

    static func jsonLDBlocks(_ html: String) -> [Any] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let body = Range(match.range(at: 1), in: html) else { return nil }
            let text = html[body].trimmingCharacters(in: .whitespacesAndNewlines)
            return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        }
    }

    static func findRecipe(_ json: Any) -> [String: Any]? {
        if let array = json as? [Any] {
            for item in array { if let hit = findRecipe(item) { return hit } }
        } else if let object = json as? [String: Any] {
            let type = object["@type"]
            let types = (type as? [String]) ?? [(type as? String) ?? ""]
            if types.contains(where: { $0.lowercased() == "recipe" }) { return object }
            if let graph = object["@graph"], let hit = findRecipe(graph) { return hit }
            if let entity = object["mainEntity"], let hit = findRecipe(entity) { return hit }
        }
        return nil
    }

    static func draft(from object: [String: Any], url: URL) -> RecipeDraft {
        var draft = RecipeDraft()
        draft.title = text(object["name"]) ?? ""
        draft.summary = text(object["description"])
        draft.sourceURL = url.absoluteString
        draft.sourceName = url.host()?.replacingOccurrences(of: "www.", with: "")
        draft.creator = author(object["author"])
        draft.imageURL = image(object["image"])
        draft.servings = recipeYield(object["recipeYield"]) ?? 0
        draft.prepMinutes = minutes(text(object["prepTime"]))
        draft.cookMinutes = minutes(text(object["cookTime"]))
        draft.totalMinutes = minutes(text(object["totalTime"]))
        draft.cuisine = list(object["recipeCuisine"]).first
        let categories = list(object["recipeCategory"]).map { $0.lowercased() }
        draft.mealTypes = MealSlot.allCases.map(\.rawValue).filter { slot in categories.contains { $0.contains(slot) } }
        draft.tags = Array(list(object["keywords"]).prefix(6))
        draft.ingredients = list(object["recipeIngredient"] ?? object["ingredients"]).map(DraftIngredient.init(line:))
        draft.steps = instructions(object["recipeInstructions"]).map { DraftStep(text: $0) }
        if let nutrition = object["nutrition"] as? [String: Any] {
            var facts = DraftNutrition()
            facts.calories = number(nutrition["calories"])
            facts.protein = number(nutrition["proteinContent"])
            facts.carbs = number(nutrition["carbohydrateContent"])
            facts.fat = number(nutrition["fatContent"])
            facts.fiber = number(nutrition["fiberContent"])
            facts.sugar = number(nutrition["sugarContent"])
            facts.sodium = number(nutrition["sodiumContent"])
            facts.source = "Published by \(draft.sourceName ?? "the website")"
            facts.total = draft.ingredients.count
            facts.matched = draft.ingredients.count
            if facts.calories > 0 { draft.nutrition = facts }
        }
        draft.method = "link"
        return draft
    }

    // MARK: Field helpers

    static func instructions(_ value: Any?) -> [String] {
        if let string = value as? String {
            return string.components(separatedBy: CharacterSet.newlines).compactMap { clean($0) }.filter { !$0.isEmpty }
        }
        guard let array = value as? [Any] else {
            if let object = value as? [String: Any] { return instructions([object]) }
            return []
        }
        return array.flatMap { item -> [String] in
            if let string = item as? String { return [clean(string)].compactMap { $0 } }
            guard let object = item as? [String: Any] else { return [] }
            if let children = object["itemListElement"] { return instructions(children) }
            return [text(object["text"]) ?? text(object["name"])].compactMap { $0 }
        }.filter { !$0.isEmpty }
    }

    static func recipeYield(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        for candidate in list(value) {
            if let match = candidate.range(of: #"\d+"#, options: .regularExpression), let count = Int(candidate[match]) {
                return count
            }
        }
        return nil
    }

    /// ISO-8601 durations like "PT1H15M" → 75.
    static func minutes(_ iso: String?) -> Int {
        guard let iso = iso?.uppercased(), iso.hasPrefix("P") else { return 0 }
        var total = 0.0
        var number = ""
        var inTime = false
        for character in iso.dropFirst() {
            if character == "T" { inTime = true; continue }
            if character.isNumber || character == "." { number.append(character); continue }
            let value = Double(number) ?? 0
            number = ""
            switch character {
            case "D": total += value * 1440
            case "H": total += value * 60
            case "M": total += inTime ? value : value * 43_200
            case "S": total += value / 60
            default: break
            }
        }
        return Int(total.rounded())
    }

    static func image(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] { return array.lazy.compactMap { image($0) }.first }
        if let object = value as? [String: Any] { return (object["url"] as? String) ?? (object["contentUrl"] as? String) }
        return nil
    }

    static func author(_ value: Any?) -> String? {
        if let string = value as? String { return clean(string) }
        if let array = value as? [Any] { return array.lazy.compactMap { author($0) }.first }
        if let object = value as? [String: Any] { return text(object["name"]) }
        return nil
    }

    static func list(_ value: Any?) -> [String] {
        if let string = value as? String {
            return string.split(separator: ",").compactMap { clean(String($0)) }.filter { !$0.isEmpty }
        }
        if let array = value as? [Any] { return array.compactMap { text($0) }.filter { !$0.isEmpty } }
        return []
    }

    static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String,
              let range = string.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return 0 }
        return Double(string[range]) ?? 0
    }

    static func text(_ value: Any?) -> String? {
        if let string = value as? String { return clean(string) }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] { return array.lazy.compactMap { text($0) }.first }
        return nil
    }

    static func meta(_ html: String, _ property: String) -> String? {
        let pattern = #"<meta[^>]+(?:property|name)\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: property) + #"["'][^>]*content\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return clean(String(html[range]))
    }

    /// Strips tags and decodes the common HTML entities.
    static func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                        "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–", "&#8212;": "—",
                        "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾", "&deg;": "°"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Turns loose text (pasted captions, OCR from photos, speech transcripts) into a draft
/// without AI. Used offline and as a starting point before the server improves it.
enum RecipeTextParser {
    private static let ingredientHeaders = ["ingredients", "ingredient", "what you need", "you will need", "you'll need", "shopping list", "for the"]
    private static let stepHeaders = ["method", "instructions", "directions", "steps", "preparation", "how to make", "how to cook", "recipe steps"]

    static func parse(_ text: String) -> RecipeDraft {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var title = ""
        var ingredients: [String] = []
        var steps: [String] = []
        enum Section { case none, ingredients, steps }
        var section = Section.none
        let sawHeaders = lines.contains { isHeader($0, ingredientHeaders) } || lines.contains { isHeader($0, stepHeaders) }

        for (index, line) in lines.enumerated() {
            if isHeader(line, ingredientHeaders) { section = .ingredients; continue }
            if isHeader(line, stepHeaders) { section = .steps; continue }
            if index == 0, title.isEmpty, line.count < 70, !looksLikeIngredient(line) {
                title = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*:"))
                continue
            }
            switch section {
            case .ingredients where sawHeaders:
                ingredients.append(line)
            case .steps where sawHeaders:
                steps.append(stripStepNumber(line))
            default:
                if looksLikeIngredient(line) { ingredients.append(line) }
                else if line.count > 25 { steps.append(stripStepNumber(line)) }
            }
        }
        var draft = RecipeDraft.from(title: title, ingredientLines: ingredients, steps: steps)
        let lower = text.lowercased()
        if let servings = firstNumber(in: lower, pattern: #"(?:serves|servings?|makes|yield)\s*:?\s*(\d+)"#) { draft.servings = servings }
        else if let servings = firstNumber(in: lower, pattern: #"(\d+)\s*(?:servings|portions|people)"#) { draft.servings = servings }
        else { draft.servings = 0 }
        if let minutes = firstNumber(in: lower, pattern: #"(\d+)\s*(?:min|mins|minutes)\b"#), minutes < 300 { draft.totalMinutes = minutes }
        return draft
    }

    static func looksLikeIngredient(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-*–—▢□◦· "))
        guard stripped.count <= 70 else { return false }
        let parsed = IngredientParser.parse(stripped)
        if parsed.quantity != nil { return !stripped.lowercased().hasPrefix("step") }
        if parsed.isVague { return true }
        return ["•", "-", "*", "▢", "□", "◦", "·"].contains { line.hasPrefix($0) } && stripped.count < 45
    }

    private static func isHeader(_ line: String, _ words: [String]) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":#*- "))
        return lower.count < 40 && words.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ":") }
    }

    private static func stripStepNumber(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(?:step\s*)?\d+[\.\):]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func firstNumber(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}
