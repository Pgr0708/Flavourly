import CoreData
import SwiftUI

// MARK: - Filters

struct RecipeFilters: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest", rating = "My rating", quickest = "Quickest", title = "A–Z"
        var id: String { rawValue }
    }
    enum History: String, CaseIterable, Identifiable {
        case all = "All", cooked = "Cooked before", untried = "Not tried yet"
        var id: String { rawValue }
    }

    var slot: MealSlot?
    var maxMinutes: Int?
    var diets: Set<Diet> = []
    var cuisines: Set<String> = []
    var history: History = .all
    var minRating = 0
    var difficulty: Difficulty?
    var equipment: Equipment?
    var maxCalories: Int?
    var minProtein: Int?
    var maxCost: Double?
    var sort: Sort = .newest

    var activeCount: Int {
        (slot == nil ? 0 : 1) + (maxMinutes == nil ? 0 : 1) + diets.count + cuisines.count
            + (history == .all ? 0 : 1) + (minRating == 0 ? 0 : 1) + (difficulty == nil ? 0 : 1)
            + (equipment == nil ? 0 : 1) + (maxCalories == nil ? 0 : 1) + (minProtein == nil ? 0 : 1) + (maxCost == nil ? 0 : 1)
    }

    func apply(to recipes: [Recipe], query: String) -> [Recipe] {
        let needle = FoodText.normalize(query).trimmingCharacters(in: .whitespaces)
        let filtered = recipes.filter { recipe in
            if !needle.isEmpty {
                let haystack = FoodText.normalize(([recipe.displayTitle, recipe.cuisine ?? "", recipe.tags ?? ""] + recipe.checkLines).joined(separator: " "))
                guard needle.split(separator: " ").allSatisfy({ haystack.contains(" \($0) ") || haystack.contains(String($0)) }) else { return false }
            }
            if let slot, !recipe.slots.contains(slot) { return false }
            if let maxMinutes, recipe.minutes == 0 || recipe.minutes > maxMinutes { return false }
            if !diets.isEmpty, diets.contains(where: { diet in recipe.checkLines.contains { FoodRules.dietViolation($0, diet: diet) != nil } }) {
                return false
            }
            if !cuisines.isEmpty, !cuisines.contains(where: { $0.caseInsensitiveCompare(recipe.cuisine ?? "") == .orderedSame }) { return false }
            if let difficulty, recipe.level > difficulty { return false }
            if let equipment {
                let needs = recipe.equipment
                // "Air fryer" shows air-fryer recipes; "Stovetop" shows recipes that need nothing else.
                if equipment == .stovetop ? !needs.isSubset(of: [.stovetop, .noCook]) || needs.isEmpty : !needs.contains(equipment) { return false }
            }
            // Unknown nutrition never passes a nutrition filter: a promise of "under 500 kcal" must be checkable.
            if let maxCalories, recipe.calories == 0 || recipe.calories > Double(maxCalories) { return false }
            if let minProtein, recipe.calories == 0 || recipe.protein < Double(minProtein) { return false }
            // Same rule for cost: only recipes priced from the cook's own shopping can promise a budget.
            if let maxCost, (recipe.costEstimate?.perServing ?? .infinity) > maxCost { return false }
            switch history {
            case .all: break
            case .cooked: if recipe.cookedCount == 0 { return false }
            case .untried: if recipe.cookedCount > 0 { return false }
            }
            return recipe.rating >= minRating
        }
        switch sort {
        case .newest: return filtered.sorted { Self.created($0) > Self.created($1) }
        case .rating: return filtered.sorted { Self.ratingKey($0) > Self.ratingKey($1) }
        case .quickest: return filtered.sorted { Self.minutesKey($0) < Self.minutesKey($1) }
        case .title: return filtered.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    private static func created(_ recipe: Recipe) -> Date { recipe.createdAt ?? .distantPast }
    private static func ratingKey(_ recipe: Recipe) -> Int { Int(recipe.rating) * 10_000 + Int(recipe.cookedCount) }
    private static func minutesKey(_ recipe: Recipe) -> Int { recipe.minutes == 0 ? 9_999 : recipe.minutes }
}

// MARK: - Cookbook tab

struct CookbookView: View {
    @Binding var sheet: RootSheet?

    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var search = CookbookSearch.shared
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
                  predicate: NSPredicate(format: "isSaved == YES AND isArchived == NO"))
    private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)])
    private var collections: FetchedResults<RecipeCollection>

    @State private var mode = 0
    @State private var filters = RecipeFilters()
    @State private var showFilters = false
    @State private var selecting = false
    @State private var selection = Set<NSManagedObjectID>()
    @State private var newCollectionName = ""
    @State private var showNewCollection = false
    @State private var showMoveSheet = false

    private var visible: [Recipe] { filters.apply(to: Array(recipes), query: search.query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                searchRow.padding(.horizontal, 20).padding(.top, 14)
                Picker("View", selection: $mode.animation(Theme.snappy)) {
                    Text("My recipes").tag(0)
                    Text("Discover").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .onChange(of: mode) { _, _ in Haptics.select() }

                if mode == 0 { myRecipes } else { DiscoverContent() }
            }
            .padding(.bottom, selecting ? 90 : 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .dockSpacing()
        .canvasBackground()
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { if selecting { selectionBar } }
        .sheet(isPresented: $showFilters) { FiltersSheet(filters: $filters) }
        .sheet(isPresented: $showMoveSheet) {
            CollectionPickerSheet(recipeIDs: Array(selection)) { endSelection() }
        }
        .alert("New collection", isPresented: $showNewCollection) {
            TextField("e.g. Weeknight", text: $newCollectionName)
            Button("Create") { createCollection() }
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookbook").font(Theme.pageTitle).foregroundStyle(Theme.ink)
                Text("\(recipes.count) saved · \(recipes.filter { $0.cookedCount > 0 }.count) cooked")
                    .font(Theme.caption).foregroundStyle(Theme.ink2)
                    .contentTransition(.numericText())
            }
            Spacer()
            if mode == 0 {
                IconButton(systemImage: selecting ? "xmark" : "checkmark.circle", label: selecting ? "Cancel selection" : "Select recipes", style: .bordered) {
                    withAnimation(Theme.spring) { selecting ? endSelection() : (selecting = true) }
                }
            }
            IconButton(systemImage: "square.and.arrow.down", label: "Import a recipe", style: .bordered) { sheet = .importLink }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Title, ingredient or tag", text: $search.query)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !search.query.isEmpty {
                    Button { search.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))

            Button {
                Haptics.primary()
                showFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(filters.activeCount > 0 ? .white : Theme.ink)
                    .frame(width: 46, height: 46)
                    .background(filters.activeCount > 0 ? AnyShapeStyle(Theme.green) : AnyShapeStyle(Color.white), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line))
                    .overlay(alignment: .topTrailing) {
                        if filters.activeCount > 0 {
                            Text("\(filters.activeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Theme.plan, in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Filter and sort, \(filters.activeCount) active")
        }
    }

    // MARK: My recipes

    @ViewBuilder
    private var myRecipes: some View {
        collectionsRow.padding(.top, 18)
        historyChips.padding(.top, 16)

        let list = visible
        HStack {
            Text(search.query.isEmpty ? "Recently saved" : "\(list.count) results")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            Spacer()
            Menu {
                Picker("Sort", selection: $filters.sort) {
                    ForEach(RecipeFilters.Sort.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filters.sort.rawValue)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            }
            .onChange(of: filters.sort) { _, _ in Haptics.select() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)

        if recipes.isEmpty {
            EmptyStateView(title: "Your cookbook is empty",
                           message: "Import from Instagram, TikTok, YouTube or any website — or save ideas from Discover.",
                           actionTitle: "Import a recipe") { sheet = .importLink }
                .padding(20)
        } else if list.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "No matches",
                           message: "Try another word or clear some filters.",
                           actionTitle: "Clear filters") {
                filters = RecipeFilters()
                search.query = ""
            }
            .padding(20)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(list) { recipe in
                    if selecting {
                        Button {
                            Haptics.tick()
                            toggle(recipe)
                        } label: {
                            RecipeGridCard(recipe: recipe, selected: selection.contains(recipe.objectID), selecting: true)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                    } else {
                        NavigationLink(value: recipe.route) { RecipeGridCard(recipe: recipe) }
                            .buttonStyle(PressableStyle(scale: 0.97))
                            .contextMenu { contextMenu(for: recipe) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private var collectionsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Collections", actionTitle: "New") { showNewCollection = true }
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    NavigationLink(value: Route.smartCollection(.favourites)) {
                        CollectionTile(title: "Favourites", count: recipes.filter(\.isFavorite).count, symbol: "heart.fill",
                                       color: Theme.plan, cover: recipes.first(where: \.isFavorite))
                    }
                    ForEach(collections) { collection in
                        NavigationLink(value: Route.collection(collection.objectID)) {
                            CollectionTile(title: collection.name ?? "Collection", count: collection.recipes?.count ?? 0,
                                           symbol: collection.symbol ?? "folder.fill", color: Color(hex: collection.colorHex ?? "#155634"),
                                           cover: (collection.recipes as? Set<Recipe>)?.first)
                        }
                    }
                    NavigationLink(value: Route.smartCollection(.quick)) {
                        CollectionTile(title: "Under 30 min", count: recipes.filter { $0.minutes > 0 && $0.minutes <= 30 }.count,
                                       symbol: "bolt.fill", color: Theme.green, cover: recipes.first { $0.minutes > 0 && $0.minutes <= 30 })
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var historyChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(RecipeFilters.History.allCases) { option in
                    Chip(title: option.rawValue, isOn: filters.history == option) { filters.history = option }
                }
                Chip(title: "≤ 30 min", isOn: filters.maxMinutes == 30) { filters.maxMinutes = filters.maxMinutes == 30 ? nil : 30 }
                Chip(title: "Rated 4★+", isOn: filters.minRating == 4) { filters.minRating = filters.minRating == 4 ? 0 : 4 }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func contextMenu(for recipe: Recipe) -> some View {
        Button {
            recipe.isFavorite.toggle()
            Kitchen.save()
            Kitchen.relearnTaste()
            Haptics.success()
        } label: {
            Label(recipe.isFavorite ? "Remove from favourites" : "Add to favourites", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
        }
        Button {
            Kitchen.duplicate(recipe)
            DropsManager.showSuccess(title: "Duplicated", subtitle: recipe.displayTitle)
        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button(role: .destructive) {
            recipe.isArchived = true
            Kitchen.save()
            DropsManager.showInfo(title: "Archived", subtitle: "Find it in Profile › Archived recipes")
        } label: { Label("Archive", systemImage: "archivebox") }
    }

    // MARK: Selection

    private var selectionBar: some View {
        HStack(spacing: 0) {
            selectionAction("Plan these", "calendar.badge.plus", Theme.green) { planSelected() }
            selectionAction("Move", "folder", Theme.ink) { showMoveSheet = true }
            selectionAction("Favourite", "heart", Theme.plan) {
                forSelected { $0.isFavorite = true }
                DropsManager.showSuccess(title: "Added to favourites")
            }
            selectionAction("Duplicate", "plus.square.on.square", Theme.ink) {
                forSelected { Kitchen.duplicate($0) }
                DropsManager.showSuccess(title: "Duplicated \(selection.count)")
            }
            selectionAction("Archive", "archivebox", Theme.allergen) {
                forSelected { $0.isArchived = true }
                Haptics.destructive()
                DropsManager.showInfo(title: "Archived \(selection.count)")
            }
        }
        .padding(.vertical, 8)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.15), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 96)
        .disabled(selection.isEmpty)
        .opacity(selection.isEmpty ? 0.6 : 1)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func selectionAction(_ title: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.primary()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private func toggle(_ recipe: Recipe) {
        if selection.contains(recipe.objectID) { selection.remove(recipe.objectID) } else { selection.insert(recipe.objectID) }
    }

    private func forSelected(_ change: (Recipe) -> Void) {
        for id in selection { if let recipe = try? Kitchen.context.existingObject(with: id) as? Recipe { change(recipe) } }
        Kitchen.save()
        endSelection()
    }

    private func endSelection() {
        selection.removeAll()
        withAnimation(Theme.spring) { selecting = false }
    }

    /// Drops the chosen recipes into the next empty dinner slots.
    private func planSelected() {
        let recipes = selection.compactMap { try? Kitchen.context.existingObject(with: $0) as? Recipe }
        var free: [Date] = []
        let taken = Set(Kitchen.meals(from: .now, days: 14).filter { $0.mealSlot == .dinner }.compactMap(\.day))
        for day in Kitchen.days(from: .now, count: 14) where !taken.contains(day) { free.append(day) }
        let eaters = People.defaultEaters(for: .dinner)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        var planned: [String] = []
        for (recipe, day) in zip(recipes, free) {
            Kitchen.plan(recipe, day: day, slot: .dinner, servings: People.servings(for: eaters), eaters: eaters)
            planned.append(formatter.string(from: day))
        }
        DropsManager.showSuccess(title: "\(planned.count) dinner\(planned.count == 1 ? "" : "s") planned", subtitle: planned.joined(separator: ", "))
        endSelection()
    }

    private func createCollection() {
        let check = Validate.collectionName(newCollectionName)
        newCollectionName = ""
        guard check.isValid else {
            Haptics.error()
            DropsManager.showError(title: "Collection not created", subtitle: check.message)
            return
        }
        let name = check.value
        let collection = RecipeCollection(context: Kitchen.context)
        collection.uuid = UUID()
        collection.name = name
        collection.createdAt = .now
        collection.sortIndex = Int16(collections.count)
        collection.colorHex = Swatch.color(for: collections.count + 1)
        collection.symbol = "folder.fill"
        Kitchen.save()
        DropsManager.showSuccess(title: "Collection created", subtitle: name)
    }
}

// MARK: - Cards

struct RecipeGridCard: View {
    @ObservedObject var recipe: Recipe
    var selected = false
    var selecting = false

    private var check: FoodCheckResult { FoodRules.check(ingredients: recipe.checkLines, profile: People.profile()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RecipeImage(recipe: recipe, cornerRadius: 0).frame(height: 118)
                HStack(spacing: 4) {
                    if recipe.needsReview { Badge(text: "Check", systemImage: "exclamationmark.triangle.fill", tone: .amber) }
                    else if recipe.cookedCount > 0 { Badge(text: "Cooked \(recipe.cookedCount)×", tone: .white) }
                    if check.isBlocked { Badge(text: "Allergen", systemImage: "exclamationmark.shield.fill", tone: .red) }
                }
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    CheckCircle(isOn: selected).padding(8)
                } else if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.plan)
                        .frame(width: 28, height: 28)
                        .background(.white, in: Circle())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if recipe.minutes > 0 { Text("\(recipe.minutes) min") }
                    if recipe.rating > 0 { Text("★ \(recipe.rating)") }
                    if let source = recipe.sourceName ?? recipe.sourceHost { Text(source).lineLimit(1) }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Theme.green : .clear, lineWidth: 3)
        }
        .shadow(color: Theme.ink.opacity(0.05), radius: 10, y: 5)
        .animation(Theme.snappy, value: selected)
    }
}

struct CollectionTile: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color
    let cover: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                if let cover {
                    RecipeImage(recipe: cover, cornerRadius: 18)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
                    .padding(8)
            }
            .frame(width: 112, height: 112)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text("\(count) recipes").font(Theme.micro).foregroundStyle(Theme.muted)
        }
        .frame(width: 112, alignment: .leading)
    }
}

// MARK: - Filters sheet

struct FiltersSheet: View {
    @Binding var filters: RecipeFilters
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecipeFilters()

    /// The cook's own cuisines first (country + recipes they have), then common ones.
    private var cuisines: [String] {
        let mine = [LocalFood.shared.cuisine] + Kitchen.candidates().compactMap(\.cuisine)
        let common = ["Italian", "Mediterranean", "Middle Eastern", "Mexican", "Chinese", "Thai", "Japanese", "American", "French"]
        let all = (mine + common).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: all)) as? [String] ?? common
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let profile = People.profile()
                    if !profile.allergens.isEmpty || !profile.customAllergens.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.allergen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allergens are always handled").font(.system(size: 14, weight: .semibold))
                                Text("\(profile.allergenSummary.capitalizedFirst) — hidden from ideas, flagged on your recipes.")
                                    .font(Theme.micro)
                            }
                            .foregroundStyle(Color(hex: "#8E2219"))
                            Spacer()
                            Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(Theme.allergen)
                        }
                        .padding(14)
                        .background(Theme.allergenSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    group("Meal") {
                        FlowLayout {
                            ForEach(MealSlot.allCases) { slot in
                                Chip(title: slot.label, isOn: draft.slot == slot) { draft.slot = draft.slot == slot ? nil : slot }
                            }
                        }
                    }
                    group("Max total time") {
                        Picker("Max total time", selection: $draft.maxMinutes) {
                            Text("Any").tag(Int?.none)
                            ForEach([15, 30, 45, 60], id: \.self) { Text("\($0) min").tag(Int?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                    group("Diet") {
                        FlowLayout {
                            ForEach(Diet.allCases) { diet in
                                Chip(title: diet.label, isOn: draft.diets.contains(diet), style: .green) {
                                    if draft.diets.contains(diet) { draft.diets.remove(diet) } else { draft.diets.insert(diet) }
                                }
                            }
                        }
                    }
                    group("Cuisine") {
                        FlowLayout {
                            ForEach(cuisines, id: \.self) { cuisine in
                                Chip(title: cuisine, isOn: draft.cuisines.contains(cuisine), style: .green) {
                                    if draft.cuisines.contains(cuisine) { draft.cuisines.remove(cuisine) } else { draft.cuisines.insert(cuisine) }
                                }
                            }
                        }
                    }
                    group("Difficulty") {
                        Picker("Difficulty", selection: $draft.difficulty) {
                            Text("Any").tag(Difficulty?.none)
                            Text("Easy").tag(Difficulty?.some(.easy))
                            Text("Easy–medium").tag(Difficulty?.some(.medium))
                        }
                        .pickerStyle(.segmented)
                    }
                    group("Equipment") {
                        FlowLayout {
                            ForEach(Equipment.allCases) { item in
                                Chip(title: item.label, isOn: draft.equipment == item) { draft.equipment = draft.equipment == item ? nil : item }
                            }
                        }
                    }
                    group("Calories per serving") {
                        Picker("Calories", selection: $draft.maxCalories) {
                            Text("Any").tag(Int?.none)
                            ForEach([300, 450, 600, 800], id: \.self) { Text("≤ \($0)").tag(Int?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                    group("Protein per serving") {
                        Picker("Protein", selection: $draft.minProtein) {
                            Text("Any").tag(Int?.none)
                            ForEach([15, 25, 35], id: \.self) { Text("≥ \($0) g").tag(Int?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                        if draft.maxCalories != nil || draft.minProtein != nil {
                            Text("Only recipes with known nutrition are shown.").font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                    }
                    group("Cost per serving") {
                        Picker("Cost", selection: $draft.maxCost) {
                            Text("Any").tag(Double?.none)
                            ForEach(PriceBook.steps(currency: Kitchen.currency), id: \.self) { Text("≤ \(Kitchen.money($0))").tag(Double?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                        Text(draft.maxCost == nil ? "Costs come from prices you add on your grocery list." : "Only recipes whose cost is known from your grocery prices are shown.")
                            .font(Theme.micro).foregroundStyle(Theme.muted)
                    }
                    group("History") {
                        Picker("History", selection: $draft.history) {
                            ForEach(RecipeFilters.History.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    group("Sort by") {
                        Picker("Sort by", selection: $draft.sort) {
                            ForEach(RecipeFilters.Sort.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Show results", systemImage: "line.3.horizontal.decrease") {
                    filters = draft
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white)
            }
            .navigationTitle("Filter & sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        Haptics.tick()
                        withAnimation(Theme.snappy) { draft = RecipeFilters() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { filters = draft; dismiss() }.bold() }
            }
            .onAppear { draft = filters }
            .onChange(of: draft.maxMinutes) { _, _ in Haptics.select() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Theme.label).tracking(0.8).foregroundStyle(Theme.muted)
            content()
        }
    }
}

/// Add recipes to one or more collections.
struct CollectionPickerSheet: View {
    let recipeIDs: [NSManagedObjectID]
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true)]) private var collections: FetchedResults<RecipeCollection>
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New collection", text: $newName)
                        Button("Add") { add() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !newName.isEmpty { FieldError(message: Validate.collectionName(newName).message) }
                }
                Section("Move to") {
                    ForEach(collections) { collection in
                        Button {
                            move(into: collection)
                        } label: {
                            HStack {
                                Image(systemName: collection.symbol ?? "folder.fill").foregroundStyle(Color(hex: collection.colorHex ?? "#155634"))
                                Text(collection.name ?? "Collection").foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(collection.recipes?.count ?? 0)").foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose a collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let check = Validate.collectionName(newName)
        guard check.isValid else {
            Haptics.error()
            return
        }
        let collection = RecipeCollection(context: Kitchen.context)
        collection.uuid = UUID()
        collection.name = check.value
        collection.createdAt = .now
        collection.colorHex = Swatch.color(for: collections.count + 1)
        collection.sortIndex = Int16(collections.count)
        newName = ""
        move(into: collection)
    }

    private func move(into collection: RecipeCollection) {
        for id in recipeIDs {
            if let recipe = try? Kitchen.context.existingObject(with: id) as? Recipe { recipe.addToCollections(collection) }
        }
        Kitchen.save()
        DropsManager.showSuccess(title: "Added to \(collection.name ?? "collection")", subtitle: "\(recipeIDs.count) recipe\(recipeIDs.count == 1 ? "" : "s")")
        onDone()
        dismiss()
    }
}

// MARK: - Collection screen

struct CollectionView: View {
    let smart: SmartCollection?
    let collection: RecipeCollection?

    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var recipes: FetchedResults<Recipe>
    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false

    init(smart: SmartCollection?, collection: RecipeCollection?) {
        self.smart = smart
        self.collection = collection
        let predicate: NSPredicate
        if let smart { predicate = smart.predicate }
        else if let collection { predicate = NSPredicate(format: "ANY collections == %@ AND isArchived == NO", collection) }
        else { predicate = NSPredicate(value: false) }
        _recipes = FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)], predicate: predicate)
    }

    private var title: String { smart?.title ?? collection?.name ?? "Collection" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.pageTitle).foregroundStyle(Theme.ink)
                    Text("\(recipes.count) recipes").font(Theme.caption).foregroundStyle(Theme.ink2)
                }
                if recipes.isEmpty {
                    EmptyStateView(systemImage: smart?.symbol ?? "folder", title: "Nothing here yet",
                                   message: smart == .archived ? "Archived recipes appear here." : "Long-press a recipe in your cookbook to add it.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(recipes) { recipe in
                            NavigationLink(value: recipe.route) { RecipeGridCard(recipe: recipe) }
                                .buttonStyle(PressableStyle(scale: 0.97))
                                .contextMenu {
                                    if smart == .archived {
                                        Button { recipe.isArchived = false; Kitchen.save(); DropsManager.showSuccess(title: "Restored") } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                        Button(role: .destructive) {
                                            Haptics.destructive()
                                            Kitchen.context.delete(recipe)
                                            Kitchen.save()
                                        } label: { Label("Delete forever", systemImage: "trash") }
                                    } else if let collection {
                                        Button { recipe.removeFromCollections(collection); Kitchen.save() } label: {
                                            Label("Remove from \(collection.name ?? "collection")", systemImage: "minus.circle")
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .padding(20)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let collection {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { name = collection.name ?? ""; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete collection", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Collection options")
                }
            }
        }
        .alert("Rename collection", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") {
                let check = Validate.collectionName(name)
                if check.isValid {
                    collection?.name = check.value
                    Kitchen.save()
                } else {
                    Haptics.error()
                    DropsManager.showError(title: "Name not changed", subtitle: check.message)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this collection? Recipes stay in your cookbook.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                if let collection { Kitchen.context.delete(collection); Kitchen.save() }
                Haptics.destructive()
                dismiss()
            }
        }
    }
}
