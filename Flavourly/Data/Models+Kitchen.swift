import CoreData
import SwiftUI

enum MealStatus: String { case planned, cooked, skipped }

enum PantryLocation: String, CaseIterable, Identifiable {
    case fridge, freezer, cupboard
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .fridge: "refrigerator.fill"
        case .freezer: "snowflake"
        case .cupboard: "cabinet.fill"
        }
    }
}

// MARK: - Recipe

extension Recipe {
    var displayTitle: String {
        let text = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled recipe" : text
    }

    /// Stable id for ranking and plan lookups (library recipes use their remote id).
    var key: String { remoteID ?? uuid?.uuidString ?? objectID.uriRepresentation().absoluteString }

    var sortedIngredients: [RecipeIngredient] {
        ((ingredients as? Set<RecipeIngredient>) ?? []).sorted { $0.position < $1.position }
    }

    var sortedSteps: [RecipeStep] {
        ((steps as? Set<RecipeStep>) ?? []).sorted { $0.position < $1.position }
    }

    var minutes: Int { totalMinutes > 0 ? Int(totalMinutes) : Int(prepMinutes + cookMinutes) }

    var tagList: [String] { Self.split(tags) }

    var slots: Set<MealSlot> {
        let stored = Set(Self.split(mealTypes).compactMap { MealSlot(rawValue: $0.lowercased()) })
        return stored.isEmpty ? MealSlot.infer(title: displayTitle, tags: tagList) : stored
    }

    /// Lines the safety rules read ("200 ml heavy cream").
    var checkLines: [String] { sortedIngredients.map(\.checkLine) }
    var hasPhoto: Bool { imageURL != nil || imageData != nil || imageName != nil }

    var reviewFlags: [ReviewFlag] {
        guard let data = reviewNotes?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ReviewFlag].self, from: data)) ?? []
    }

    var sourceHost: String? {
        guard let sourceURL, let host = URL(string: sourceURL)?.host() else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var hasNutrition: Bool { calories > 0 }

    var collectionList: [RecipeCollection] {
        ((collections as? Set<RecipeCollection>) ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var stepTexts: [String] { sortedSteps.compactMap(\.text) }

    /// Cost per serving from the cook's own grocery prices; nil until 70% of ingredients are priced.
    var costEstimate: PriceBook.Estimate? {
        PriceBook.estimate(ingredients: sortedIngredients.map { ($0.name ?? "", $0.quantity > 0 ? $0.quantity : nil, $0.unit ?? "") },
                           servings: Int(servings), prices: Kitchen.prices(),
                           isStaple: { GroceryBuilder.staples.contains(FoodText.key($0)) })
    }
    var level: Difficulty { RecipeTraits.difficulty(steps: stepTexts, ingredientCount: sortedIngredients.count, minutes: minutes) }
    var equipment: Set<Equipment> { RecipeTraits.equipment(steps: stepTexts) }

    var facts: RecipeFacts {
        RecipeFacts(
            id: key, title: displayTitle, ingredientNames: checkLines, minutes: minutes, slots: slots,
            cuisine: cuisine, tags: tagList, rating: Int(rating), isFavorite: isFavorite, cookedCount: Int(cookedCount),
            lastCooked: lastCookedAt, protein: protein, calories: calories, carbs: carbs,
            difficulty: level, equipment: equipment
        )
    }

    func draft() -> RecipeDraft {
        var draft = RecipeDraft()
        draft.title = displayTitle
        draft.summary = summary
        draft.sourceURL = sourceURL
        draft.sourceName = sourceName
        draft.creator = creator
        draft.imageURL = imageURL
        draft.imageName = imageName
        draft.servings = Int(servings)
        draft.prepMinutes = Int(prepMinutes)
        draft.cookMinutes = Int(cookMinutes)
        draft.totalMinutes = Int(totalMinutes)
        draft.cuisine = cuisine
        draft.mealTypes = Self.split(mealTypes)
        draft.tags = tagList
        draft.ingredients = sortedIngredients.map { $0.draft }
        draft.steps = sortedSteps.map { DraftStep(text: $0.text ?? "", timerSeconds: Int($0.timerSeconds), confidence: $0.confidence) }
        if hasNutrition {
            draft.nutrition = DraftNutrition(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber,
                                             sugar: sugar, sodium: sodium, matched: Int(nutritionMatched), total: Int(nutritionTotal),
                                             source: nutritionSource)
        }
        draft.flags = reviewFlags
        draft.method = importMethod
        draft.remoteID = remoteID
        return draft
    }

    static func split(_ csv: String?) -> [String] {
        (csv ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Ingredient & step

extension RecipeIngredient {
    var checkLine: String {
        let base = originalText?.isEmpty == false ? originalText! : (name ?? "")
        return base
    }

    var draft: DraftIngredient {
        var item = DraftIngredient(line: originalText ?? name ?? "")
        item.quantity = quantity > 0 ? quantity : nil
        item.quantityMax = quantityMax > 0 ? quantityMax : nil
        item.unit = unit ?? ""
        item.name = name ?? item.name
        item.note = note
        item.confidence = confidence
        item.isOptional = isOptional
        return item
    }

    func amount(system: UnitSystem, scale: Double) -> String {
        Amount.text(quantity: quantity > 0 ? quantity : nil, max: quantityMax > 0 ? quantityMax : nil,
                    unit: unit ?? "", system: system, scale: scale)
    }
}

// MARK: - Plan

extension PlannedMeal {
    var mealSlot: MealSlot { MealSlot(rawValue: slot ?? "") ?? .dinner }
    var mealStatus: MealStatus { MealStatus(rawValue: status ?? "") ?? .planned }
    var title: String { customTitle ?? recipe?.displayTitle ?? "Meal" }
    var eaterIDs: [String] { Recipe.split(eaters) }
    /// Servings to cook, including extra portions for planned leftovers.
    var cookServings: Int { Int(servings + extraServings) }
    var leftoverChildren: [PlannedMeal] { Array((leftoverMeals as? Set<PlannedMeal>) ?? []) }
}

// MARK: - Pantry

extension PantryItem {
    var locationKind: PantryLocation { PantryLocation(rawValue: location ?? "") ?? .cupboard }

    var daysLeft: Int? {
        guard let expiresAt else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: expiresAt)).day
    }

    var expiryText: String? {
        guard let days = daysLeft else { return nil }
        switch days {
        case ..<0: return "Expired"
        case 0: return "Use today"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }

    var displayName: String { (name ?? "").capitalizedFirst }
}

// MARK: - Household

extension HouseholdMember {
    var displayName: String { (name ?? "").isEmpty ? "Someone" : name! }
    var initial: String { String(displayName.prefix(1)).uppercased() }
    var color: Color { Color(hex: colorHex ?? "#C7631F") }
}

extension GroceryItem {
    var displayName: String { (name ?? "").capitalizedFirst }
}
