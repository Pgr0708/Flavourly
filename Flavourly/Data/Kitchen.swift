import CoreData
import Foundation

/// All writes go through here so rules (leftovers, locks, cooked counts, grocery state) live in one place.
@MainActor
enum Kitchen {
    static var context: NSManagedObjectContext { CoreDataManager.shared.context }

    static func save() { CoreDataManager.shared.save() }

    // MARK: - Recipes

    @discardableResult
    static func save(_ draft: RecipeDraft, into existing: Recipe? = nil, imageData: Data? = nil,
                     in target: NSManagedObjectContext? = nil, commit: Bool = true) -> Recipe {
        let draft = draft.sanitized()
        let ctx = target ?? context
        let recipe = existing ?? Recipe(context: ctx)
        if existing == nil {
            recipe.uuid = UUID()
            recipe.createdAt = .now
            recipe.isSaved = true
        }
        recipe.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summary = draft.summary
        recipe.sourceURL = draft.sourceURL
        recipe.sourceName = draft.sourceName
        recipe.creator = draft.creator
        recipe.imageURL = draft.imageURL
        recipe.imageName = draft.imageName ?? recipe.imageName
        if let imageData { recipe.imageData = imageData }
        recipe.servings = Int16(clamping: max(1, draft.servings))
        recipe.prepMinutes = Int16(clamping: draft.prepMinutes)
        recipe.cookMinutes = Int16(clamping: draft.cookMinutes)
        recipe.totalMinutes = Int16(clamping: draft.minutes)
        recipe.cuisine = draft.cuisine
        recipe.mealTypes = draft.mealTypes.joined(separator: ",")
        recipe.tags = draft.tags.joined(separator: ",")
        recipe.importMethod = draft.method ?? recipe.importMethod
        recipe.remoteID = draft.remoteID ?? recipe.remoteID
        recipe.updatedAt = .now

        for old in recipe.sortedIngredients { ctx.delete(old) }
        for (index, item) in draft.ingredients.enumerated() {
            let ingredient = RecipeIngredient(context: ctx)
            ingredient.uuid = UUID()
            ingredient.position = Int16(clamping: index)
            ingredient.quantity = item.quantity ?? 0
            ingredient.quantityMax = item.quantityMax ?? 0
            ingredient.unit = item.unit
            ingredient.name = item.name
            ingredient.note = item.note
            ingredient.originalText = item.text.isEmpty ? item.displayLine : item.text
            ingredient.aisle = Aisle.classify(item.name).rawValue
            ingredient.isOptional = item.isOptional
            ingredient.confidence = item.confidence
            ingredient.recipe = recipe
        }
        for old in recipe.sortedSteps { ctx.delete(old) }
        for (index, item) in draft.steps.enumerated() where !item.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let step = RecipeStep(context: ctx)
            step.uuid = UUID()
            step.position = Int16(clamping: index)
            step.text = item.text
            step.timerSeconds = Int32(clamping: item.timerSeconds)
            step.confidence = item.confidence
            step.recipe = recipe
        }
        if let nutrition = draft.nutrition {
            recipe.calories = nutrition.calories
            recipe.protein = nutrition.protein
            recipe.carbs = nutrition.carbs
            recipe.fat = nutrition.fat
            recipe.fiber = nutrition.fiber
            recipe.sugar = nutrition.sugar
            recipe.sodium = nutrition.sodium
            recipe.nutritionMatched = Int16(clamping: nutrition.matched)
            recipe.nutritionTotal = Int16(clamping: nutrition.total)
        }
        recipe.needsReview = !draft.flags.isEmpty
        recipe.reviewNotes = draft.flags.isEmpty ? nil : (try? JSONEncoder().encode(draft.flags)).flatMap { String(data: $0, encoding: .utf8) }
        if commit, target == nil { save() }
        return recipe
    }

    /// Library recipes live in memory; anything the user saves or plans is copied into their kitchen.
    @discardableResult
    static func adopt(_ recipe: Recipe) -> Recipe {
        if recipe.managedObjectContext === context { return recipe }
        if let remoteID = recipe.remoteID,
           let existing = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "remoteID == %@", remoteID), limit: 1).first {
            if !existing.isSaved { existing.isSaved = true; save() }
            return existing
        }
        var draft = recipe.draft()
        draft.remoteID = recipe.remoteID
        draft.method = draft.method ?? "library"
        let copy = save(draft, imageData: recipe.imageData)
        copy.isCurated = recipe.isCurated
        save()
        return copy
    }

    static func findDuplicate(of draft: RecipeDraft) -> Recipe? {
        if let url = draft.sourceURL, !url.isEmpty,
           let match = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "sourceURL == %@ AND isArchived == NO", url), limit: 1).first {
            return match
        }
        let key = FoodText.key(draft.title)
        guard key.split(separator: " ").count >= 2 else { return nil }
        return CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "isSaved == YES AND isArchived == NO")).first {
            let other = FoodText.key($0.displayTitle)
            return other == key || (other.count > 6 && (other.contains(key) || key.contains(other)))
        }
    }

    @discardableResult
    static func duplicate(_ recipe: Recipe) -> Recipe {
        var draft = recipe.draft()
        draft.title += " (copy)"
        draft.remoteID = nil
        let copy = save(draft, imageData: recipe.imageData)
        copy.collections = recipe.collections
        save()
        return copy
    }

    /// Counts a cook once and ticks off the matching planned meal (today's, when none is given).
    static func recordCooked(_ recipe: Recipe, rating: Int? = nil, note: String? = nil, meal: PlannedMeal? = nil) {
        let target = adopt(recipe)
        let planned = meal ?? meals(from: .now, days: 1).first { $0.recipe == target && $0.mealStatus == .planned && !$0.isLeftover }
        planned?.status = MealStatus.cooked.rawValue
        target.cookedCount += 1
        target.lastCookedAt = .now
        if let rating, rating > 0 { target.rating = Int16(rating) }
        if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty {
            let stamp = Date.now.formatted(date: .abbreviated, time: .omitted)
            target.notes = [target.notes, "\(stamp): \(note)"].compactMap { $0 }.joined(separator: "\n")
        }
        save()
    }

    static func recipe(forKey key: String) -> Recipe? {
        if let uuid = UUID(uuidString: key),
           let hit = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "uuid == %@", uuid as CVarArg), limit: 1).first {
            return hit
        }
        if let hit = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "remoteID == %@", key), limit: 1).first { return hit }
        return Library.shared.recipe(id: key)
    }

    /// Everything the recommender may suggest: the user's recipes plus library recipes they haven't saved.
    static func candidates() -> [Recipe] {
        let mine = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "isSaved == YES AND isArchived == NO"))
        let saved = Set(mine.compactMap(\.remoteID))
        return mine + Library.shared.recipes.filter { !saved.contains($0.remoteID ?? "") && LocalFood.shared.allows($0) }
    }

    // MARK: - Plan

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    static func weekStart(_ date: Date = .now) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func days(from start: Date, count: Int = 7) -> [Date] {
        (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start)) }
    }

    static func meals(from start: Date, days count: Int = 7) -> [PlannedMeal] {
        let begin = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: count, to: begin) else { return [] }
        return CoreDataManager.shared.fetch(
            PlannedMeal.self, NSPredicate(format: "day >= %@ AND day < %@", begin as NSDate, end as NSDate),
            sort: [NSSortDescriptor(key: "day", ascending: true), NSSortDescriptor(key: "sortIndex", ascending: true)]
        )
    }

    @discardableResult
    static func plan(_ recipe: Recipe?, customTitle: String? = nil, day: Date, slot: MealSlot, servings: Int,
                     eaters: [String], extra: Int = 0, byAI: Bool = false, reason: String? = nil,
                     leftoverOf source: PlannedMeal? = nil, locked: Bool = false) -> PlannedMeal {
        let meal = PlannedMeal(context: context)
        meal.uuid = UUID()
        meal.createdAt = .now
        meal.day = calendar.startOfDay(for: day)
        meal.slot = slot.rawValue
        meal.recipe = recipe.map(adopt)
        meal.customTitle = customTitle
        meal.servings = Int16(clamping: max(1, servings))
        meal.extraServings = Int16(clamping: max(0, extra))
        meal.eaters = eaters.joined(separator: ",")
        meal.createdByAI = byAI
        meal.aiReason = reason
        meal.isLocked = locked
        meal.status = MealStatus.planned.rawValue
        meal.sortIndex = Int16(clamping: meals(from: day, days: 1).filter { $0.mealSlot == slot }.count)
        if let source {
            meal.isLeftover = true
            meal.leftoverSource = source
            source.extraServings += meal.servings
        }
        save()
        NotificationService.shared.reschedule()
        return meal
    }

    static func remove(_ meal: PlannedMeal) {
        if let source = meal.leftoverSource {
            source.extraServings = max(0, source.extraServings - meal.servings)
        }
        for child in meal.leftoverChildren { context.delete(child) }
        context.delete(meal)
        save()
        NotificationService.shared.reschedule()
    }

    static func move(_ meal: PlannedMeal, to day: Date, slot: MealSlot) {
        meal.day = calendar.startOfDay(for: day)
        meal.slot = slot.rawValue
        save()
        NotificationService.shared.reschedule()
    }

    @discardableResult
    static func duplicate(_ meal: PlannedMeal, to day: Date, slot: MealSlot) -> PlannedMeal {
        plan(meal.recipe, customTitle: meal.customTitle, day: day, slot: slot, servings: Int(meal.servings), eaters: meal.eaterIDs)
    }

    static func setStatus(_ meal: PlannedMeal, _ status: MealStatus) {
        let wasCooked = meal.mealStatus == .cooked
        meal.status = status.rawValue
        if status == .cooked, !wasCooked, !meal.isLeftover, let recipe = meal.recipe {
            recipe.cookedCount += 1
            recipe.lastCookedAt = .now
        }
        save()
    }

    /// Swaps the dish in a meal; leftovers planned from it follow.
    static func replace(_ meal: PlannedMeal, with recipe: Recipe?, customTitle: String? = nil, reason: String? = nil) {
        meal.recipe = recipe.map(adopt)
        meal.customTitle = customTitle
        meal.aiReason = reason
        meal.createdByAI = false
        for child in meal.leftoverChildren {
            child.recipe = meal.recipe
            child.customTitle = customTitle
        }
        save()
        NotificationService.shared.reschedule()
    }

    static func setServings(_ meal: PlannedMeal, _ servings: Int) {
        meal.servings = Int16(clamping: max(1, servings))
        save()
    }

    static func toggleLock(_ meal: PlannedMeal) {
        meal.isLocked.toggle()
        save()
    }

    /// Changes who eats a meal; servings follow portions unless the user set them by hand.
    static func setEaters(_ meal: PlannedMeal, _ ids: [String]) {
        meal.eaters = ids.joined(separator: ",")
        meal.servings = Int16(clamping: People.servings(for: ids))
        save()
    }

    // MARK: - Grocery

    static func groceryInputs(weekStart start: Date) -> [GroceryInput] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return meals(from: start).flatMap { meal -> [GroceryInput] in
            guard meal.mealStatus != .skipped, !meal.isLeftover, let recipe = meal.recipe else { return [] }
            let factor = Double(meal.cookServings) / Double(max(recipe.servings, 1))
            let when = "\(formatter.string(from: meal.day ?? .now)) \(meal.mealSlot.rawValue)"
            return recipe.sortedIngredients.filter { !$0.isOptional }.map {
                GroceryInput(recipeTitle: recipe.displayTitle, when: when, name: $0.name ?? "",
                             quantity: $0.quantity > 0 ? $0.quantity * factor : nil, unit: $0.unit ?? "")
            }
        }
    }

    static func pantryStock() -> [PantryStock] {
        CoreDataManager.shared.fetch(PantryItem.self).map {
            PantryStock(name: $0.name ?? "", quantity: $0.quantity > 0 ? $0.quantity : nil, unit: $0.unit ?? "")
        }
    }

    static func groceryLines(weekStart start: Date, system: UnitSystem) -> [GroceryLine] {
        GroceryBuilder.build(groceryInputs(weekStart: start), pantry: pantryStock(), system: system)
    }

    /// Per-week state for generated lines (checked, "I already have some", hidden).
    static func groceryState(weekStart start: Date) -> [String: GroceryItem] {
        let rows = CoreDataManager.shared.fetch(GroceryItem.self, NSPredicate(format: "isManual == NO AND weekStart == %@", start as NSDate))
        return Dictionary(rows.map { ($0.key ?? "", $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func stateRow(key: String, weekStart start: Date) -> GroceryItem {
        if let row = groceryState(weekStart: start)[key] { return row }
        let row = GroceryItem(context: context)
        row.uuid = UUID()
        row.key = key
        row.weekStart = start
        row.isManual = false
        row.createdAt = .now
        return row
    }

    /// Manual items are not tied to a week, so a plan refresh can never remove them.
    static func manualItems() -> [GroceryItem] {
        CoreDataManager.shared.fetch(GroceryItem.self, NSPredicate(format: "isManual == YES"),
                                     sort: [NSSortDescriptor(key: "createdAt", ascending: true)])
    }

    @discardableResult
    static func addManualItem(_ text: String) -> GroceryItem? {
        let check = Validate.itemName(text)
        guard check.isValid else { return nil }
        let trimmed = String(check.value.prefix(Validate.Limit.itemName + 20))
        let parsed = IngredientParser.parse(trimmed)
        let item = GroceryItem(context: context)
        item.uuid = UUID()
        item.isManual = true
        item.name = parsed.name.isEmpty ? trimmed : parsed.name
        item.quantity = parsed.quantity ?? 0
        item.unit = parsed.unit
        item.aisle = Aisle.classify(item.name ?? trimmed).rawValue
        item.key = "manual|" + FoodText.key(item.name ?? trimmed)
        item.createdAt = .now
        save()
        return item
    }

    static func clearCheckedManualItems() {
        for item in manualItems() where item.isChecked { context.delete(item) }
        save()
    }

    // MARK: - Pantry

    @discardableResult
    static func addPantry(name: String, quantity: Double? = nil, unit: String = "", location: PantryLocation? = nil,
                          expires: Date? = nil) -> PantryItem {
        let name = String(Sanitize.text(name).prefix(Validate.Limit.itemName))
        let key = FoodText.key(name)
        let existing = CoreDataManager.shared.fetch(PantryItem.self).first { FoodText.key($0.name ?? "") == key }
        let item = existing ?? PantryItem(context: context)
        if existing == nil {
            item.uuid = UUID()
            item.createdAt = .now
            item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let quantity, quantity > 0 {
            if existing != nil, item.unit == unit { item.quantity += quantity } else { item.quantity = quantity; item.unit = unit }
        }
        item.location = (location ?? defaultLocation(for: name)).rawValue
        item.expiresAt = expires ?? item.expiresAt ?? defaultExpiry(for: name)
        item.isLow = false
        item.updatedAt = .now
        save()
        NotificationService.shared.reschedule()
        return item
    }

    static func pantrySignals() -> [PantrySignal] {
        CoreDataManager.shared.fetch(PantryItem.self).map {
            PantrySignal(key: FoodText.key($0.name ?? ""), name: $0.displayName, daysLeft: $0.daysLeft)
        }
    }

    static func defaultLocation(for name: String) -> PantryLocation {
        switch Aisle.classify(name) {
        case .dairy, .meat, .chilled: .fridge
        case .frozen: .freezer
        case .produce:
            ["tomato", "potato", "onion", "garlic", "banana", "avocado", "lemon", "lime"].contains { name.lowercased().contains($0) } ? .cupboard : .fridge
        default: .cupboard
        }
    }

    /// Rough shelf life so "use soon" works without typing dates.
    static func defaultExpiry(for name: String) -> Date? {
        let days: Int?
        switch Aisle.classify(name) {
        case .produce: days = ["spinach", "lettuce", "herb", "basil", "coriander", "mint", "berry"].contains { name.lowercased().contains($0) } ? 3 : 6
        case .dairy: days = name.lowercased().contains("egg") ? 21 : 7
        case .meat: days = 2
        case .chilled: days = 7
        case .bakery: days = 4
        default: days = nil
        }
        return days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
    }

    // MARK: - Nutrition log

    @discardableResult
    static func log(recipe: Recipe?, title: String? = nil, servings: Double = 1, slot: MealSlot, date: Date = .now,
                    memberIDs: [String] = [Person.meID], calories: Double? = nil) -> [MealLog] {
        let people = People.all()
        let logs: [MealLog] = memberIDs.map { id in
            let portion = people.first { $0.id == id }?.portion ?? 1
            let log = MealLog(context: context)
            log.uuid = UUID()
            log.createdAt = .now
            log.date = date
            log.slot = slot.rawValue
            log.title = title ?? recipe?.displayTitle ?? "Meal"
            log.servings = servings * portion
            log.memberID = id
            log.recipe = recipe.map(adopt)
            log.calories = (calories ?? recipe?.calories ?? 0) * log.servings
            log.protein = (recipe?.protein ?? 0) * log.servings
            log.carbs = (recipe?.carbs ?? 0) * log.servings
            log.fat = (recipe?.fat ?? 0) * log.servings
            return log
        }
        save()
        HealthService.shared.write(logs.filter { $0.memberID == Person.meID })
        return logs
    }

    static func logs(on day: Date, member: String = Person.meID) -> [MealLog] {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return CoreDataManager.shared.fetch(
            MealLog.self,
            NSPredicate(format: "date >= %@ AND date < %@ AND memberID == %@", start as NSDate, end as NSDate, member),
            sort: [NSSortDescriptor(key: "date", ascending: true)]
        )
    }

    // MARK: - Erase

    static func eraseEverything() {
        for entity in ["Recipe", "RecipeIngredient", "RecipeStep", "RecipeCollection", "PlannedMeal", "GroceryItem", "PantryItem", "HouseholdMember", "MealLog"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in (try? context.fetch(request)) ?? [] { context.delete(object) }
        }
        save()
    }
}
