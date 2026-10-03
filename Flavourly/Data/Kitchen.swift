import CoreData
internal import Combine
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
        if let nutrition = draft.nutrition { apply(nutrition, to: recipe) }
        recipe.needsReview = !draft.flags.isEmpty
        recipe.reviewNotes = draft.flags.isEmpty ? nil : (try? JSONEncoder().encode(draft.flags)).flatMap { String(data: $0, encoding: .utf8) }
        if commit, target == nil {
            save()
            if !recipe.hasPhoto { Task { await fillMissingPhotos() } }
        }
        return recipe
    }

    /// Finds a free, credited photo for saved recipes that have none (never GPT, not counted against
    /// the free plan). Dishes with no match are retried after 3 days, like the server.
    static func fillMissingPhotos(limit: Int = 15) async {
        guard !isFillingPhotos else { return }
        isFillingPhotos = true
        defer { isFillingPhotos = false }
        let saved = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "isSaved == YES AND imageURL == nil AND imageData == nil AND imageName == nil"))
        // Built-in recipes without a photo too (they live in memory; found photos are remembered by Library).
        let bare = saved + Library.shared.recipes.filter { $0.imageURL == nil && $0.imageData == nil && Library.needsBetterPhoto($0.imageName) }
        var tried = UserDefaults.standard.dictionary(forKey: "photoLookups") as? [String: Double] ?? [:]
        let now = Date.now.timeIntervalSince1970
        for recipe in bare.prefix(limit + 40) {
            let title = recipe.displayTitle
            guard title != "Untitled recipe", now - (tried[title.lowercased()] ?? 0) > 3 * 86_400 else { continue }
            tried[title.lowercased()] = now
            guard let url = try? await AIService.freePhotoURL(title: title), !recipe.isDeleted, recipe.imageURL == nil, recipe.imageData == nil else { continue }
            recipe.objectWillChange.send()
            recipe.imageURL = url
            if !recipe.isSaved { recipe.imageName = nil } // a sharp web photo replaces a tiny bundled one
            if recipe.isSaved { save() } else { Library.foundPhotos[title.lowercased()] = url }
        }
        UserDefaults.standard.set(tried.filter { now - $0.value < 3 * 86_400 }, forKey: "photoLookups")
    }
    private static var isFillingPhotos = false

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
        Personalizer.shared.finishedCooking(recipe)
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
        let used = usePantry(for: target, servings: planned.map { Int($0.cookServings) } ?? Int(target.servings))
        save()
        relearnTaste()
        if !used.isEmpty {
            let list = used.prefix(3).joined(separator: ", ") + (used.count > 3 ? "…" : "")
            DropsManager.showInfo(title: "Pantry updated", subtitle: String(format: Lang.text("Used %@"), list))
        }
    }

    /// Re-learns what this cook likes from everything they've cooked, rated or favourited.
    static func relearnTaste() {
        let mine = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "cookedCount > 0 OR rating > 0 OR isFavorite == YES"))
        RankContext.taste = TasteProfile.learn(from: mine.map {
            TasteProfile.Signal(facts: $0.facts, cookedCount: Int($0.cookedCount), rating: Int($0.rating), isFavorite: $0.isFavorite, lastCooked: $0.lastCookedAt)
        })
    }

    /// Takes what a cook used out of the pantry (same unit family only; nothing is guessed across
    /// g↔cups). Items that run out are kept and marked "running low" so they can go on the list.
    @discardableResult
    static func usePantry(for recipe: Recipe, servings: Int) -> [String] {
        let stock = CoreDataManager.shared.fetch(PantryItem.self)
        guard !stock.isEmpty else { return [] }
        let factor = Double(max(1, servings)) / Double(max(1, recipe.servings))
        var used: [String] = []
        for ingredient in recipe.sortedIngredients where ingredient.quantity > 0 && !ingredient.isOptional {
            let key = FoodText.key(ingredient.name ?? "")
            guard !key.isEmpty, let item = stock.first(where: { Recommender.matches(key, FoodText.key($0.name ?? "")) }), item.quantity > 0 else { continue }
            let need = ingredient.quantity * factor
            let needUnit = ingredient.unit ?? ""
            let haveUnit = item.unit ?? ""
            let amount: Double?
            if let a = Units.toBase(need, unit: needUnit), let b = Units.toBase(1, unit: haveUnit), Units.family(needUnit) == Units.family(haveUnit) {
                amount = a / b
            } else if needUnit == haveUnit || (["", "piece"].contains(needUnit) && ["", "piece"].contains(haveUnit)) {
                amount = need
            } else {
                amount = nil
            }
            guard let amount else { continue }
            item.quantity = max(0, item.quantity - amount)
            if item.quantity < 0.001 { item.isLow = true }
            item.updatedAt = .now
            used.append(item.displayName.lowercased())
        }
        return used
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

    static func apply(_ nutrition: DraftNutrition, to recipe: Recipe) {
        recipe.calories = nutrition.calories
        recipe.protein = nutrition.protein
        recipe.carbs = nutrition.carbs
        recipe.fat = nutrition.fat
        recipe.fiber = nutrition.fiber
        recipe.sugar = nutrition.sugar
        recipe.sodium = nutrition.sodium
        recipe.nutritionMatched = Int16(clamping: nutrition.matched)
        recipe.nutritionTotal = Int16(clamping: nutrition.total)
        recipe.nutritionSource = nutrition.source
    }

    /// After ingredients change (editor, swaps), recalculates from USDA/Spoonacular on the server.
    /// If the new list can't be verified, the old numbers stay but are labelled as outdated.
    static func refreshNutrition(_ recipe: Recipe) async {
        let lines = recipe.sortedIngredients.map { $0.originalText ?? $0.name ?? "" }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        do {
            if let fresh = try await AIService.nutrition(lines: lines, servings: Int(recipe.servings)) {
                apply(fresh, to: recipe)
            } else if recipe.calories > 0 {
                recipe.nutritionSource = "Estimate from before your edits"
            }
            save()
        } catch {
            // Offline: keep the old numbers; the next edit tries again.
        }
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
        if status == .skipped, let key = meal.recipe?.key { Personalizer.shared.record(.skip, recipe: key) }
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
        if meal.isLocked, let key = meal.recipe?.key { Personalizer.shared.record(.lock, recipe: key) }
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

    // MARK: - Prices (budget)

    static var currency: String { Locale.current.currency?.identifier ?? "USD" }

    /// Saves what the cook paid; the newest price per food is what recipe costs use.
    static func recordPrice(name: String, price: Double, quantity: Double?, unit: String) {
        let key = FoodText.key(name)
        guard !key.isEmpty, price > 0 else { return }
        let entry = PriceEntry(context: context)
        entry.uuid = UUID()
        entry.key = key
        entry.name = String(Sanitize.text(name).prefix(Validate.Limit.itemName))
        entry.price = price
        entry.quantity = (quantity ?? 0) > 0 ? quantity! : 1
        entry.unit = (quantity ?? 0) > 0 ? unit : "piece"
        entry.currency = currency
        entry.date = .now
        save()
        priceCache = nil
    }

    private static var priceCache: (at: Date, prices: [String: PricePoint])?

    /// Latest price per food in the cook's currency (a minute's cache: list filters ask for every recipe).
    static func prices() -> [String: PricePoint] {
        if let cache = priceCache, Date.now.timeIntervalSince(cache.at) < 60 { return cache.prices }
        let rows = CoreDataManager.shared.fetch(PriceEntry.self, NSPredicate(format: "currency == %@", currency),
                                                sort: [NSSortDescriptor(key: "date", ascending: true)])
        var latest: [String: PricePoint] = [:]
        for row in rows {
            latest[row.key ?? ""] = PricePoint(key: row.key ?? "", name: row.name ?? "", price: row.price, quantity: row.quantity,
                                               unit: row.unit ?? "", currency: row.currency ?? "", date: row.date ?? .distantPast)
        }
        priceCache = (.now, latest)
        return latest
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(value < 10 ? 2 : 0)))
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
            PantrySignal(key: FoodText.key($0.name ?? ""), name: $0.displayName, daysLeft: $0.daysLeft,
                         quantity: $0.quantity, unit: $0.unit ?? "")
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
