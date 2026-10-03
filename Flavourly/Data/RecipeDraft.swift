import Foundation

/// The one shape a recipe has before it is saved: imports, AI ideas, the editor and the
/// bundled library all produce a draft, and Review Import edits a draft.
struct RecipeDraft: Codable, Equatable {
    var title = ""
    var summary: String?
    var sourceURL: String?
    var sourceName: String?
    var creator: String?
    var imageURL: String?
    var imageName: String?
    var servings = 2
    var prepMinutes = 0
    var cookMinutes = 0
    var totalMinutes = 0
    var cuisine: String?
    var mealTypes: [String] = []
    var tags: [String] = []
    var ingredients: [DraftIngredient] = []
    var steps: [DraftStep] = []
    var nutrition: DraftNutrition?
    /// Things the importer is unsure about, shown as "Please check".
    var flags: [ReviewFlag] = []
    var method: String?
    var remoteID: String?

    var minutes: Int {
        if totalMinutes > 0 { return totalMinutes }
        return prepMinutes + cookMinutes
    }

    var hasContent: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty }

    enum CodingKeys: String, CodingKey {
        case title, summary, sourceURL, sourceName, creator, imageURL, imageName, servings, prepMinutes, cookMinutes,
             totalMinutes, cuisine, mealTypes, tags, ingredients, steps, nutrition, flags, method, remoteID
    }

    init() {}

    /// Lenient decoding: the backend and bundled JSON may leave any field out.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        summary = try? c.decode(String.self, forKey: .summary)
        sourceURL = try? c.decode(String.self, forKey: .sourceURL)
        sourceName = try? c.decode(String.self, forKey: .sourceName)
        creator = try? c.decode(String.self, forKey: .creator)
        imageURL = try? c.decode(String.self, forKey: .imageURL)
        imageName = try? c.decode(String.self, forKey: .imageName)
        servings = max(1, (try? c.decode(Int.self, forKey: .servings)) ?? 2)
        prepMinutes = max(0, (try? c.decode(Int.self, forKey: .prepMinutes)) ?? 0)
        cookMinutes = max(0, (try? c.decode(Int.self, forKey: .cookMinutes)) ?? 0)
        totalMinutes = max(0, (try? c.decode(Int.self, forKey: .totalMinutes)) ?? 0)
        cuisine = try? c.decode(String.self, forKey: .cuisine)
        mealTypes = (try? c.decode([String].self, forKey: .mealTypes)) ?? []
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        ingredients = (try? c.decode([DraftIngredient].self, forKey: .ingredients)) ?? []
        steps = (try? c.decode([DraftStep].self, forKey: .steps)) ?? []
        nutrition = try? c.decode(DraftNutrition.self, forKey: .nutrition)
        flags = (try? c.decode([ReviewFlag].self, forKey: .flags)) ?? []
        method = try? c.decode(String.self, forKey: .method)
        remoteID = try? c.decode(String.self, forKey: .remoteID)
    }

    /// Builds a draft from plain ingredient lines and steps (text paste, OCR, bundled recipes).
    static func from(title: String, ingredientLines: [String], steps: [String], servings: Int = 2) -> RecipeDraft {
        var draft = RecipeDraft()
        draft.title = title
        draft.servings = servings
        draft.ingredients = ingredientLines.map(DraftIngredient.init(line:))
        draft.steps = steps.map { DraftStep(text: $0) }
        return draft
    }
}

struct DraftIngredient: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var quantity: Double?
    var quantityMax: Double?
    var unit = ""
    var name: String
    var note: String?
    var confidence: Double = 1
    var isOptional = false

    init(line: String) {
        let parsed = IngredientParser.parse(line)
        text = line
        quantity = parsed.quantity
        quantityMax = parsed.quantityMax
        unit = parsed.unit
        name = parsed.name
        note = parsed.note
        confidence = parsed.confidence
        isOptional = parsed.isOptional
    }

    enum CodingKeys: String, CodingKey { case text, quantity, quantityMax, unit, name, note, confidence, isOptional }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let line = (try? c.decode(String.self, forKey: .text)) ?? ""
        let parsed = IngredientParser.parse(line)
        text = line
        quantity = (try? c.decode(Double.self, forKey: .quantity)) ?? parsed.quantity
        quantityMax = (try? c.decode(Double.self, forKey: .quantityMax)) ?? parsed.quantityMax
        let decodedUnit = (try? c.decode(String.self, forKey: .unit)) ?? parsed.unit
        unit = Units.canonical(decodedUnit) ?? decodedUnit
        name = (try? c.decode(String.self, forKey: .name)).flatMap { $0.isEmpty ? nil : $0 } ?? parsed.name
        note = (try? c.decode(String.self, forKey: .note)) ?? parsed.note
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? parsed.confidence
        isOptional = (try? c.decode(Bool.self, forKey: .isOptional)) ?? parsed.isOptional
    }

    /// The line to show and to run allergen checks on.
    var displayLine: String {
        let amount = Amount.text(quantity: quantity, max: quantityMax, unit: unit, system: .metric)
        let base = [amount, name].filter { !$0.isEmpty }.joined(separator: " ")
        return note.map { "\(base), \($0)" } ?? base
    }
}

struct DraftStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var timerSeconds = 0
    var confidence: Double = 1

    init(text: String, timerSeconds: Int? = nil, confidence: Double = 1) {
        self.text = text
        self.timerSeconds = timerSeconds ?? StepTimer.seconds(in: text)
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey { case text, timerSeconds, confidence }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        timerSeconds = (try? c.decode(Int.self, forKey: .timerSeconds)) ?? StepTimer.seconds(in: text)
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 1
    }
}

struct DraftNutrition: Codable, Equatable {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var fiber = 0.0
    var sugar = 0.0
    var sodium = 0.0
    var matched = 0
    var total = 0
    var source: String?
}

struct ReviewFlag: Codable, Equatable, Hashable, Identifiable {
    /// "title", "servings", "time", "ingredient:3", "step:1", "duplicate"
    var field: String
    var message: String
    var id: String { field + message }
}

/// Finds "30 seconds", "10 minutes", "1 hour" in a step so Cook Mode can offer a timer.
enum StepTimer {
    static func seconds(in text: String) -> Int {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:-|–|to)?\s*(\d+(?:\.\d+)?)?\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return 0 }
        func group(_ index: Int) -> String? {
            guard let r = Range(match.range(at: index), in: text) else { return nil }
            return String(text[r])
        }
        // Use the upper end of a range ("8–10 minutes" → 10 minutes).
        guard let value = Double(group(2) ?? group(1) ?? "") else { return 0 }
        let unit = (group(3) ?? "").lowercased()
        let multiplier: Double = unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1
        let seconds = Int(value * multiplier)
        return (5...(6 * 3600)).contains(seconds) ? seconds : 0
    }
}

extension RecipeDraft {
    /// Cleans every text field and clamps every number — the last guard before anything is stored,
    /// whether it came from the editor, an import, AI or the bundled library.
    func sanitized() -> RecipeDraft {
        func clean(_ text: String?, _ max: Int, multiline: Bool = false) -> String? {
            guard let text else { return nil }
            let value = String(Sanitize.text(text, multiline: multiline).prefix(max))
            return value.isEmpty ? nil : value
        }
        func link(_ text: String?) -> String? {
            guard let text = clean(text, Validate.Limit.link), let url = URL(string: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return text
        }
        var draft = self
        draft.title = clean(title, Validate.Limit.title) ?? ""
        draft.summary = clean(summary, Validate.Limit.summary)
        draft.sourceURL = link(sourceURL)
        draft.imageURL = link(imageURL)
        draft.sourceName = clean(sourceName, 100)
        draft.creator = clean(creator, 100)
        draft.cuisine = clean(cuisine, Validate.Limit.cuisine)
        draft.servings = min(max(servings, 1), 100)
        draft.prepMinutes = min(max(prepMinutes, 0), 2880)
        draft.cookMinutes = min(max(cookMinutes, 0), 2880)
        draft.totalMinutes = min(max(totalMinutes, 0), 2880)
        draft.mealTypes = Array(Set(mealTypes.map { $0.lowercased() }).intersection(["breakfast", "lunch", "dinner", "snack"])).sorted()
        // "null"/"none" as text (from older server answers) is not a tag.
        let realTags = tags.compactMap { clean($0, Validate.Limit.tag) }.filter { !["null", "none", "n/a", "unknown"].contains($0.lowercased()) }
        draft.tags = Array((NSOrderedSet(array: realTags).array as? [String] ?? []).prefix(Validate.Limit.tags))
        draft.ingredients = Array(ingredients.compactMap { item -> DraftIngredient? in
            var item = item
            item.text = clean(item.text, Validate.Limit.ingredient) ?? ""
            item.name = clean(item.name, 120) ?? IngredientParser.parse(item.text).name
            item.note = clean(item.note, 120)
            item.unit = clean(item.unit, 20) ?? ""
            item.quantity = item.quantity.flatMap { $0.isFinite && $0 > 0 ? min($0, 100_000) : nil }
            item.quantityMax = item.quantityMax.flatMap { $0.isFinite && $0 > (item.quantity ?? 0) ? min($0, 100_000) : nil }
            item.confidence = min(max(item.confidence.isFinite ? item.confidence : 0.5, 0), 1)
            return item.text.isEmpty && item.name.isEmpty ? nil : item
        }.prefix(Validate.Limit.ingredients))
        draft.steps = Array(steps.compactMap { step -> DraftStep? in
            guard let text = clean(step.text, Validate.Limit.step, multiline: true) else { return nil }
            return DraftStep(text: text, timerSeconds: min(max(step.timerSeconds, 0), 86_400),
                             confidence: min(max(step.confidence.isFinite ? step.confidence : 0.5, 0), 1))
        }.prefix(Validate.Limit.steps))
        if var nutrition {
            func clamp(_ value: Double, _ max: Double) -> Double { value.isFinite ? min(Swift.max(value, 0), max) : 0 }
            nutrition.calories = clamp(nutrition.calories, 20_000)
            nutrition.protein = clamp(nutrition.protein, 2_000)
            nutrition.carbs = clamp(nutrition.carbs, 2_000)
            nutrition.fat = clamp(nutrition.fat, 2_000)
            nutrition.fiber = clamp(nutrition.fiber, 500)
            nutrition.sugar = clamp(nutrition.sugar, 2_000)
            nutrition.sodium = clamp(nutrition.sodium, 50_000)
            nutrition.matched = max(0, nutrition.matched)
            nutrition.total = max(nutrition.matched, nutrition.total)
            nutrition.source = nutrition.source.map { String(Sanitize.text($0).prefix(60)) }
            draft.nutrition = nutrition
        }
        draft.flags = Array(flags.compactMap { flag in
            clean(flag.message, 200).map { ReviewFlag(field: String(flag.field.prefix(40)), message: $0) }
        }.prefix(50))
        return draft
    }
}
