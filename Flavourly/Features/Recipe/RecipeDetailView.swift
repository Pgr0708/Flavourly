import CoreData
import SwiftUI

struct RecipeDetailView: View {
    @ObservedObject var recipe: Recipe

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var servings = 2
    @State private var section = 0
    @State private var swapTarget: RecipeIngredient?
    @State private var showPlanSheet = false
    @State private var showCook = false
    @State private var showEditor = false
    @State private var showCollections = false
    @State private var confirmDelete = false
    @State private var perServing = true
    @State private var notes = ""
    @State private var generatingImage = false
    @State private var didLoad = false
    @State private var openedRoute: Route?
    /// Swaps chosen "just for this cook" (ingredient → replacement line, "" = left out). The saved recipe is untouched.
    @State private var swaps: [UUID: String] = [:]

    private var scale: Double { Double(servings) / Double(max(recipe.servings, 1)) }
    private var cookLines: [String] {
        recipe.sortedIngredients.compactMap { item in
            guard let id = item.uuid, let swap = swaps[id] else { return item.checkLine }
            return swap.isEmpty ? nil : swap
        }
    }
    private var check: FoodCheckResult { FoodRules.check(ingredients: cookLines, profile: People.profile(), carbsPerServing: recipe.carbs) }
    private var isLibrary: Bool { !recipe.isSaved }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    MakeItMyWayButton(recipe: recipe) { openedRoute = $0 }.padding(.top, 14)
                    safetyBanner.padding(.top, 14)
                    if recipe.needsReview && !recipe.reviewFlags.isEmpty { reviewCard.padding(.top, 12) }
                    tabs.padding(.top, 16)
                    Group {
                        switch section {
                        case 0: ingredients
                        case 1: steps
                        case 2: NutritionPanel(recipe: recipe, perServing: $perServing)
                        default: notesPanel
                        }
                    }
                    .padding(.top, 12)
                    .animation(Theme.gentle, value: section)
                    // Under the ingredients and steps: videos of the dish being made.
                    if section <= 1 { RecipeVideosRow(title: recipe.displayTitle).padding(.top, 24) }
                    // Last: other cooks' own versions of this dish, from the same region first.
                    NearbyVersionsSection(title: recipe.displayTitle) { openedRoute = $0 }.padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
                .background(Theme.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .offset(y: -28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .canvasBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationDestination(item: $openedRoute) { RouteView(route: $0) }
        .sheet(item: $swapTarget) { ingredient in
            SubstituteSheet(recipe: recipe, ingredient: ingredient, swaps: $swaps, scale: scale).environmentObject(settings)
        }
        .sheet(isPresented: $showPlanSheet) { AddToPlanSheet(recipe: recipe).environmentObject(settings) }
        .sheet(isPresented: $showEditor) { NavigationStack { RecipeEditorView(recipe: Kitchen.adopt(recipe)) } }
        .sheet(isPresented: $showCollections) {
            CollectionPickerSheet(recipeIDs: [Kitchen.adopt(recipe).objectID]) {}
        }
        .fullScreenCover(isPresented: $showCook) {
            CookFlowView(recipe: recipe, servings: servings, swaps: swaps).environmentObject(settings)
        }
        .confirmationDialog("Delete \(recipe.displayTitle)? This can't be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                Haptics.destructive()
                Kitchen.context.delete(recipe)
                Kitchen.save()
                dismiss()
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            Personalizer.shared.record(.view, recipe: recipe.key)
            servings = max(1, Int(recipe.servings))
            notes = recipe.notes ?? ""
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .top) {
            RecipeImage(recipe: recipe, cornerRadius: 0, isHero: true).frame(height: 300)
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center).frame(height: 300)
            HStack {
                IconButton(systemImage: "chevron.left", label: "Back", style: .dark) { dismiss() }
                Spacer()
                if isLibrary {
                    IconButton(systemImage: "bookmark", label: "Save to cookbook", style: .dark) {
                        Kitchen.adopt(recipe)
                        DropsManager.showSuccess(title: "Saved to your cookbook", subtitle: recipe.displayTitle)
                    }
                } else {
                    IconButton(systemImage: recipe.isFavorite ? "heart.fill" : "heart", label: recipe.isFavorite ? "Remove from favourites" : "Add to favourites",
                               style: .dark, tint: recipe.isFavorite ? Color(hex: "#FF7AA2") : .white) {
                        recipe.isFavorite.toggle()
                        Kitchen.save()
                        Kitchen.relearnTaste()
                        recipe.isFavorite ? Haptics.success() : Haptics.tick()
                    }
                }
                ShareLink(item: shareText, subject: Text(recipe.displayTitle)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .accessibilityLabel("Share recipe")
                Menu {
                    Button { showEditor = true } label: { Label("Edit recipe", systemImage: "pencil") }
                    Button { showCollections = true } label: { Label("Add to collection", systemImage: "folder.badge.plus") }
                    Button {
                        let copy = Kitchen.duplicate(Kitchen.adopt(recipe))
                        DropsManager.showSuccess(title: "Duplicated", subtitle: copy.displayTitle)
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    if recipe.imageData == nil && recipe.imageName == nil {
                        Button { generatePhoto() } label: { Label("Create a photo with AI", systemImage: "sparkles") }
                    }
                    if !isLibrary {
                        Button {
                            recipe.isArchived = true
                            Kitchen.save()
                            DropsManager.showInfo(title: "Archived", subtitle: "Restore it from Profile › Archived")
                            dismiss()
                        } label: { Label("Archive", systemImage: "archivebox") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .accessibilityLabel("More actions")
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            if generatingImage {
                ProgressView("Creating a photo…").tint(.white).foregroundStyle(.white).padding(.top, 140)
            }
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = recipe.creator ?? recipe.sourceName ?? recipe.sourceHost {
                sourceLine(source)
            }
            Text(recipe.displayTitle).font(Theme.display(32)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary).font(Theme.body).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                StarRating(rating: Int(recipe.rating)) { value in
                    let target = Kitchen.adopt(recipe)
                    target.rating = Int16(value)
                    Kitchen.save()
                    Kitchen.relearnTaste()
                }
                Text(recipe.cookedCount > 0
                     ? "Cooked \(recipe.cookedCount)×\(recipe.lastCookedAt.map { ", last on \($0.formatted(.dateTime.day().month()))" } ?? "")"
                     : "Not cooked yet")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 14) {
                meta("clock", durationText(recipe.minutes))
                if recipe.calories > 0 { meta("flame", "\(Int(recipe.calories)) kcal a serving") }
                meta("person.2", plural(Int(recipe.servings), "serving"))
            }
            .padding(.top, 2)
            if let cost = recipe.costEstimate {
                Label("≈ \(Kitchen.money(cost.perServing)) a serving · from your prices for \(cost.priced) of \(cost.total) ingredients",
                      systemImage: "tag.fill")
                    .font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.pantry)
            }
        }
    }

    private func sourceLine(_ label: String) -> some View {
        Group {
            if let link = recipe.sourceURL, let url = URL(string: link) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "link").font(.system(size: 11, weight: .bold))
                        Text("\(label) · view original").font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink2)
                }
            } else {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink2)
            }
        }
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink2)
    }

    // MARK: Safety

    @ViewBuilder
    private var safetyBanner: some View {
        let result = check
        let contains = result.contains.map(\.label).sorted().joined(separator: ", ").lowercased()
        if result.isBlocked {
            banner(symbol: "exclamationmark.shield.fill", tint: Theme.allergen, background: Theme.allergenSoft,
                   title: "Not safe as written", lines: result.issues.filter { $0.severity == .blocked }.map(\.reason),
                   footnote: "Tap the ingredient to swap it — swaps are re-checked too.")
        } else if result.needsCheck {
            banner(symbol: "exclamationmark.triangle.fill", tint: Theme.check, background: Theme.checkSoft,
                   title: "Please check", lines: result.issues.map(\.reason), footnote: nil)
        } else {
            banner(symbol: "checkmark.shield.fill", tint: Theme.green, background: Theme.greenTint,
                   title: People.profile().isEmpty ? "No allergies set" : "Free from your household's allergens",
                   lines: contains.isEmpty ? [] : ["Contains \(contains)"], footnote: nil)
        }
    }

    private func banner(symbol: String, tint: Color, background: Color, title: String, lines: [String], footnote: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                ForEach(lines.prefix(4), id: \.self) { Text($0).font(Theme.micro).foregroundStyle(Theme.ink2) }
                if let footnote { Text(footnote).font(Theme.micro).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("From your import — please check", systemImage: "checklist").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.check)
            ForEach(recipe.reviewFlags.filter { !$0.field.hasPrefix("allergen") }.prefix(5)) { flag in
                Text("• \(flag.message)").font(Theme.micro).foregroundStyle(Theme.ink2)
            }
            HStack {
                Button("Edit recipe") { showEditor = true }.font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("All checked") {
                    recipe.needsReview = false
                    recipe.reviewNotes = nil
                    Kitchen.save()
                    DropsManager.showSuccess(title: "Marked as checked")
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.check)
        }
        .padding(12)
        .background(Theme.checkSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 22) {
            ForEach(Array(["Ingredients", "Steps", "Nutrition", "Notes"].enumerated()), id: \.offset) { index, title in
                Button {
                    Haptics.select()
                    section = index
                } label: {
                    Text(title)
                        .font(.system(size: 15, weight: section == index ? .bold : .medium))
                        .foregroundStyle(section == index ? Theme.green : Theme.muted)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if section == index { Capsule().fill(Theme.green).frame(height: 2.5).offset(y: 1) }
                        }
                }
                .accessibilityAddTraits(section == index ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StepperPill(value: $servings, range: 1...40)
                Text("servings").font(Theme.caption).foregroundStyle(Theme.ink2)
                Spacer()
                Picker("Units", selection: Binding(get: { settings.unitSystem }, set: { settings.unitSystem = $0; Haptics.select() })) {
                    ForEach(UnitSystem.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 128)
            }
            .padding(.bottom, 6)
            Text("Tap an ingredient to swap it.").font(Theme.micro).foregroundStyle(Theme.muted).padding(.vertical, 4)
            let issues = check.issues
            ForEach(recipe.sortedIngredients) { ingredient in
                let swap = ingredient.uuid.flatMap { swaps[$0] }
                let problem = swap == nil ? issues.first { $0.ingredient == ingredient.checkLine } : issues.first { $0.ingredient == swap }
                Button {
                    Haptics.tick()
                    swapTarget = ingredient
                } label: {
                    HStack(spacing: 12) {
                        IngredientIcon(name: swap.map { IngredientParser.parse($0).name } ?? ingredient.name ?? "", size: 36)
                            .opacity(swap == "" ? 0.4 : 1)
                        VStack(alignment: .leading, spacing: 2) {
                            if let swap {
                                Text(swap.isEmpty ? (ingredient.name ?? "") : swap)
                                    .font(.system(size: 15, weight: .medium))
                                    .strikethrough(swap.isEmpty)
                                    .foregroundStyle(swap.isEmpty ? Theme.muted : Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Text(swap.isEmpty ? "Left out · just this cook" : "Instead of \(ingredient.name ?? "") · just this cook")
                                    .font(Theme.micro).foregroundStyle(Theme.pantry)
                            } else {
                                (Text(ingredient.amount(system: settings.unitSystem, scale: scale)).bold() + Text(" " + (ingredient.name ?? "")))
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                            }
                            if swap == nil, let note = ingredient.note { Text(note).font(Theme.micro).foregroundStyle(Theme.muted) }
                            if swap == nil, let from = ingredient.substitutedFrom { Text("Swapped for \(from)").font(Theme.micro).foregroundStyle(Theme.pantry) }
                            if let problem { Text(problem.reason).font(.system(size: 12, weight: .semibold)).foregroundStyle(problem.severity == .blocked ? Theme.allergen : Theme.check) }
                        }
                        Spacer()
                        if problem != nil {
                            Badge(text: "Swap", systemImage: "arrow.left.arrow.right", tone: problem?.severity == .blocked ? .red : .amber)
                        } else if ingredient.isOptional {
                            Badge(text: "Optional", tone: .neutral)
                        }
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.5)
            }
            Button {
                addIngredientsToList()
            } label: {
                Label("Add ingredients to grocery list", systemImage: "basket")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .padding(.vertical, 12)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            if recipe.sortedSteps.isEmpty {
                EmptyStateView(systemImage: "list.number", title: "No steps yet", message: "Add the method so Cook Mode can guide you.",
                               actionTitle: "Add steps") { showEditor = true }
            }
            ForEach(Array(recipe.sortedSteps.enumerated()), id: \.element.objectID) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.green)
                        .frame(width: 28, height: 28)
                        .background(Theme.greenSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.text ?? "").font(.system(size: 16)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        if step.timerSeconds > 0 {
                            Badge(text: timerText(Int(step.timerSeconds)), systemImage: "timer", tone: .green)
                        }
                    }
                }
            }
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $notes)
                .font(Theme.hand(17))
                .frame(minHeight: 140)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Your tweaks, swaps, who loved it…").font(Theme.hand(17)).foregroundStyle(Theme.muted).padding(16).allowsHitTesting(false)
                    }
                }
            let check = Validate.optional(notes, field: "Notes", max: Validate.Limit.notes, multiline: true)
            HStack {
                FieldError(message: check.message)
                Spacer()
                CharacterCount(count: check.value.count, limit: Validate.Limit.notes)
            }
            PrimaryButton(title: "Save notes", tone: .soft, isEnabled: check.isValid, height: 44) {
                let target = Kitchen.adopt(recipe)
                target.notes = check.value.isEmpty ? nil : check.value
                Kitchen.save()
                DropsManager.showSuccess(title: "Notes saved")
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            barButton("calendar.badge.plus", "Add to plan") { showPlanSheet = true }
            barButton("basket", "Add ingredients to grocery list") { addIngredientsToList() }
            PrimaryButton(title: "Start cooking", systemImage: "flame.fill", tone: .green) { showCook = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.white.shadow(.drop(color: Theme.ink.opacity(0.06), radius: 8, y: -2)))
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.primary()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 54, height: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private var shareText: String {
        var lines = [recipe.displayTitle, ""]
        lines += recipe.sortedIngredients.map { "• " + [$0.amount(system: settings.unitSystem, scale: scale), $0.name ?? ""].joined(separator: " ") }
        lines.append("")
        lines += recipe.sortedSteps.enumerated().map { "\($0.offset + 1). \($0.element.text ?? "")" }
        if let source = recipe.sourceURL { lines += ["", "Source: \(source)"] }
        lines += ["", "Shared from Flavourly"]
        return lines.joined(separator: "\n")
    }

    private func addIngredientsToList() {
        let lines = recipe.sortedIngredients.filter { !$0.isOptional }.compactMap { item -> String? in
            if let id = item.uuid, let swap = swaps[id] { return swap.isEmpty ? nil : swap }
            return [item.amount(system: settings.unitSystem, scale: scale), item.name ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        }
        lines.forEach { Kitchen.addManualItem($0) }
        DropsManager.showSuccess(title: "Added \(plural(lines.count, "item")) to your list", subtitle: "For \(plural(servings, "serving"))")
    }

    private func generatePhoto() {
        generatingImage = true
        Task {
            defer { generatingImage = false }
            do {
                // Free photo first; an AI photo only for Premium when nothing free matches.
                let free = try? await AIService.freePhotoURL(title: recipe.displayTitle)
                if free == nil && !settings.isPremium {
                    DropsManager.showInfo(title: "No free photo yet", subtitle: "AI photos are part of Premium.")
                    Paywall.show()
                    return
                }
                let url: String
                if let free { url = free } else { url = try await AIService.recipeImageURL(title: recipe.displayTitle, summary: recipe.summary) }
                let target = Kitchen.adopt(recipe)
                target.imageURL = url
                Kitchen.save()
                DropsManager.showSuccess(title: "Photo created")
            } catch {
                DropsManager.showError(title: "Couldn't create a photo", subtitle: error.localizedDescription)
            }
        }
    }

    private func timerText(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min timer" : "\(seconds) sec timer"
    }
}

struct StarRating: View {
    let rating: Int
    var size: CGFloat = 16
    let onRate: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    Haptics.impact(.light, intensity: 0.5 + Double(value) * 0.1)
                    onRate(value == rating ? 0 : value)
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(value <= rating ? Theme.star : Color(hex: "#C9CDD2"))
                        .symbolEffect(.bounce, value: rating == value)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) stars")
            }
        }
    }
}

// MARK: - Nutrition tab

struct NutritionPanel: View {
    @ObservedObject var recipe: Recipe
    @Binding var perServing: Bool

    private var factor: Double { perServing ? 1 : Double(max(recipe.servings, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !recipe.hasNutrition {
                EmptyStateView(systemImage: "chart.pie", title: "No nutrition yet",
                               message: "Imports estimate it automatically. You can still cook and plan this recipe.")
            } else {
                Picker("Amount", selection: $perServing) {
                    Text("Per serving").tag(true)
                    Text("Whole dish").tag(false)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 20) {
                    MacroRing(protein: recipe.protein, carbs: recipe.carbs, fat: recipe.fat) {
                        VStack(spacing: 0) {
                            Text("\(Int(recipe.calories * factor))").font(Theme.rounded(26)).contentTransition(.numericText())
                            Text("kcal").font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 118, height: 118)
                    VStack(alignment: .leading, spacing: 12) {
                        macroRow("Protein", recipe.protein * factor, color: Theme.green)
                        macroRow("Carbs", recipe.carbs * factor, color: Theme.premium)
                        macroRow("Fat", recipe.fat * factor, color: Color(hex: "#E45AC6"))
                    }
                }
                .card()

                Text("Fibre \(Int(recipe.fiber * factor)) g · Sugars \(Int(recipe.sugar * factor)) g · Sodium \(Int(recipe.sodium * factor)) mg")
                    .font(Theme.micro).foregroundStyle(Theme.muted)

                let me = People.me()
                if perServing, me.calorieTarget > 0 || me.proteinTarget > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Against your daily targets").font(.system(size: 15, weight: .semibold))
                        if me.calorieTarget > 0 { target("Calories", recipe.calories, Double(me.calorieTarget), unit: "kcal", color: Theme.green) }
                        if me.proteinTarget > 0 { target("Protein", recipe.protein, Double(me.proteinTarget), unit: "g", color: Theme.green) }
                    }
                    .card()
                }

                if recipe.nutritionTotal > 0, recipe.nutritionMatched < recipe.nutritionTotal {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.check)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Estimated from \(recipe.nutritionMatched) of \(recipe.nutritionTotal) ingredients")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.check)
                            Text("Some items couldn't be matched and were left out. Fix amounts in the editor to improve it.")
                                .font(Theme.micro).foregroundStyle(Color(hex: "#5C3A00"))
                        }
                    }
                    .padding(12)
                    .background(Theme.checkSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    let verified = recipe.nutritionSource?.contains("USDA") == true || recipe.nutritionSource?.contains("Spoonacular") == true
                    Label(verified ? "Calculated from \(recipe.nutritionSource ?? "") data — not medical advice."
                                   : "\(recipe.nutritionSource ?? "Estimate") from the recipe's ingredients — not medical advice.",
                          systemImage: verified ? "checkmark.seal.fill" : "sparkles")
                        .font(Theme.micro).foregroundStyle(verified ? Theme.green : Theme.muted)
                }

                PrimaryButton(title: "Log 1 serving to today", systemImage: "plus", tone: .outline, height: 46) {
                    let slot = MealSlot.allCases.first { recipe.slots.contains($0) } ?? .dinner
                    Kitchen.log(recipe: recipe, slot: slot)
                    DropsManager.showSuccess(title: "Logged", subtitle: "\(Int(recipe.calories)) kcal added to today")
                }
            }
        }
    }

    private func macroRow(_ title: String, _ grams: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer()
            Text("\(Int(grams.rounded())) g").font(Theme.rounded(15)).contentTransition(.numericText())
        }
    }

    private func target(_ title: String, _ value: Double, _ goal: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(value)) of \(Int(goal)) \(unit)").font(Theme.micro).foregroundStyle(Theme.muted)
            }
            ProgressView(value: min(value / max(goal, 1), 1)).tint(color)
        }
    }
}

/// Donut of calories from protein, carbs and fat.
struct MacroRing<Center: View>: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    @ViewBuilder let center: () -> Center

    var body: some View {
        let p = protein * 4, c = carbs * 4, f = fat * 9
        let total = max(p + c + f, 1)
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 14)
            ring(from: 0, to: p / total, color: Theme.green)
            ring(from: p / total, to: (p + c) / total, color: Theme.premium)
            ring(from: (p + c) / total, to: 1, color: Color(hex: "#E45AC6"))
            center()
        }
        .padding(7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(Int(protein)) grams, carbs \(Int(carbs)) grams, fat \(Int(fat)) grams")
    }

    private func ring(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: from, to: max(from, to - 0.004))
            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}
