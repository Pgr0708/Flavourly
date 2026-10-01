import SwiftUI

/// Every import lands here first: unclear amounts, allergens and duplicates are shown
/// before anything is saved, and each can be fixed in place.
struct ImportReviewView: View {
    let imageData: Data?
    let onDone: (Recipe?) -> Void

    @EnvironmentObject private var settings: SettingsManager
    @State private var draft: RecipeDraft
    @State private var doubtfulIngredients: Set<UUID>
    @State private var doubtfulSteps: Set<UUID>
    @State private var servingsGuessed: Bool
    @State private var timeMissing: Bool
    @State private var duplicate: Recipe?
    @State private var replaceDuplicate = false
    @State private var confirmDiscard = false
    @State private var showErrors = false
    @FocusState private var focused: UUID?
    private let originalTexts: [UUID: String]

    init(draft: RecipeDraft, imageData: Data?, onDone: @escaping (Recipe?) -> Void) {
        self.imageData = imageData
        self.onDone = onDone
        _draft = State(initialValue: draft)
        _doubtfulIngredients = State(initialValue: Set(draft.ingredients.filter { $0.confidence < 1 }.map(\.id)))
        _doubtfulSteps = State(initialValue: Set(draft.steps.filter { $0.confidence < 1 }.map(\.id)))
        _servingsGuessed = State(initialValue: draft.flags.contains { $0.field == "servings" })
        _timeMissing = State(initialValue: draft.minutes == 0)
        originalTexts = Dictionary(draft.ingredients.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
    }

    private var profile: FoodProfile { People.profile() }

    private func issues(for item: DraftIngredient) -> [FoodIssue] {
        FoodRules.check(ingredients: [item.text.isEmpty ? item.displayLine : item.text], profile: profile).issues
    }

    private var allergenCount: Int { draft.ingredients.filter { issues(for: $0).contains { $0.severity == .blocked } }.count }
    private var checkCount: Int {
        doubtfulIngredients.count + doubtfulSteps.count + (servingsGuessed ? 1 : 0) + (timeMissing ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    summary
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Recipe name", text: $draft.title, axis: .vertical)
                            .font(Theme.display(28))
                        let title = Validate.recipeTitle(draft.title)
                        FieldError(message: showErrors || !draft.title.isEmpty ? title.message : nil)
                    }
                    if let duplicate { duplicateCard(duplicate) }
                    basics
                    ingredientsSection
                    stepsSection
                    if let nutrition = draft.nutrition, nutrition.calories > 0 { nutritionCard(nutrition) }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvasBackground()
            .navigationTitle("Review recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { confirmDiscard = true }.tint(Theme.allergen)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .confirmationDialog("Discard this import?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    Haptics.destructive()
                    onDone(nil)
                }
            } message: {
                Text("Nothing will be saved.")
            }
        }
        .onAppear { if duplicate == nil { duplicate = Kitchen.findDuplicate(of: draft) } }
    }

    // MARK: Sections

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let link = draft.imageURL, let url = URL(string: link) {
                    RemoteImage(url: url) {
                        RecipeArt(title: draft.title, cuisine: draft.cuisine).shimmering()
                    } failure: {
                        RecipeArt(title: draft.title, cuisine: draft.cuisine)
                    }
                } else {
                    RecipeArt(title: draft.title, cuisine: draft.cuisine)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            if let source = draft.creator ?? draft.sourceName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Imported from \(source)").lineLimit(1)
                    if let link = draft.sourceURL, let url = URL(string: link) {
                        Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                            .accessibilityLabel("Open the original")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            summaryPill(count: checkCount, symbol: "exclamationmark.triangle.fill",
                        text: checkCount == 0 ? "Nothing unclear" : "\(checkCount) to check", tint: checkCount == 0 ? Theme.green : Theme.check,
                        background: checkCount == 0 ? Theme.greenTint : Theme.checkSoft)
            summaryPill(count: allergenCount, symbol: allergenCount == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        text: allergenCount == 0 ? (profile.isEmpty ? "No allergies set" : "Allergen-safe") : "\(allergenCount) not safe",
                        tint: allergenCount == 0 ? Theme.green : Theme.allergen,
                        background: allergenCount == 0 ? Theme.greenTint : Theme.allergenSoft)
        }
    }

    private func summaryPill(count: Int, symbol: String, text: String, tint: Color, background: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentTransition(.numericText())
            .animation(Theme.snappy, value: count)
    }

    private func duplicateCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RecipeImage(recipe: recipe, cornerRadius: 10).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looks like one you have").font(.system(size: 14, weight: .semibold))
                    Text("\u{201C}\(recipe.displayTitle)\u{201D}\(recipe.createdAt.map { ", saved \($0.formatted(.dateTime.day().month()))" } ?? "")")
                        .font(Theme.micro).foregroundStyle(Theme.ink2).lineLimit(2)
                }
            }
            Toggle(isOn: $replaceDuplicate) {
                Text("Update that recipe instead of adding a new one").font(.system(size: 14))
            }
            .tint(Theme.green)
            .onChange(of: replaceDuplicate) { _, _ in Haptics.toggle() }
        }
        .padding(14)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var basics: some View {
        VStack(spacing: 0) {
            Stepper(value: $draft.servings, in: 1...40) {
                flaggedLabel("Serves \(draft.servings)", systemImage: "person.2", flag: servingsGuessed ? "We guessed — please check" : nil)
            }
            .onChange(of: draft.servings) { _, _ in servingsGuessed = false; Haptics.step() }
            .padding(.vertical, 8)
            Divider()
            Stepper(value: $draft.prepMinutes, in: 0...600, step: 5) {
                flaggedLabel("Prep \(draft.prepMinutes == 0 ? "—" : durationText(draft.prepMinutes))", systemImage: "hand.raised",
                             flag: timeMissing ? "No time was given" : nil)
            }
            .onChange(of: draft.prepMinutes) { _, _ in timeFixed() }
            .padding(.vertical, 8)
            Divider()
            Stepper(value: $draft.cookMinutes, in: 0...720, step: 5) {
                flaggedLabel("Cook \(draft.cookMinutes == 0 ? "—" : durationText(draft.cookMinutes))", systemImage: "flame", flag: nil)
            }
            .onChange(of: draft.cookMinutes) { _, _ in timeFixed() }
            .padding(.vertical, 8)
        }
        .card(padding: 14)
    }

    private func flaggedLabel(_ title: String, systemImage: String, flag: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage).font(.system(size: 15, weight: .medium))
            if let flag { Text(flag).font(Theme.micro).foregroundStyle(Theme.check) }
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients · \(draft.ingredients.count)").font(Theme.section)
            ForEach($draft.ingredients) { $item in ingredientRow($item) }
            Button {
                let item = DraftIngredient(line: "")
                withAnimation(Theme.snappy) { draft.ingredients.append(item) }
                focused = item.id
            } label: {
                Label("Add ingredient", systemImage: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
            }
            .tint(Theme.green)
        }
    }

    private func ingredientRow(_ item: Binding<DraftIngredient>) -> some View {
        let value = item.wrappedValue
        let problems = issues(for: value)
        let blocked = problems.first { $0.severity == .blocked }
        let doubtful = doubtfulIngredients.contains(value.id)
        let tint: Color = blocked != nil ? Theme.allergen : (doubtful || !problems.isEmpty ? Theme.check : Theme.line)
        return HStack(alignment: .top, spacing: 10) {
            IngredientIcon(name: IngredientParser.parse(value.text).name, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Ingredient", text: item.text, axis: .vertical)
                    .font(.system(size: 15))
                    .focused($focused, equals: value.id)
                    .onChange(of: value.text) { _, _ in doubtfulIngredients.remove(value.id) }
                if let invalid = Validate.ingredientLine(value.text).message {
                    FieldError(message: invalid)
                } else if let blocked {
                    Text(blocked.reason).font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.allergen)
                } else if let first = problems.first {
                    Text(first.reason).font(Theme.micro).foregroundStyle(Theme.check)
                } else if doubtful {
                    Text(value.quantity == nil ? "Amount unclear — please check" : "Please check this line").font(Theme.micro).foregroundStyle(Theme.check)
                }
            }
            Spacer(minLength: 0)
            Menu {
                if blocked != nil || !problems.isEmpty {
                    let options = swaps(for: value)
                    if options.isEmpty { Text("No safe quick swaps") }
                    ForEach(options, id: \.self) { line in
                        Button(line) { replace(value.id, with: line) }
                    }
                }
                if doubtful {
                    Button("Looks right") { doubtfulIngredients.remove(value.id); Haptics.tick() }
                }
                Button(role: .destructive) {
                    Haptics.destructive()
                    withAnimation(Theme.snappy) { draft.ingredients.removeAll { $0.id == value.id } }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                if blocked != nil {
                    Badge(text: "Swap", systemImage: "arrow.left.arrow.right", tone: .red)
                } else {
                    Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                }
            }
            .accessibilityLabel("Options for \(value.name)")
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint, lineWidth: tint == Theme.line ? 1 : 1.5))
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Method · \(draft.steps.count) steps").font(Theme.section)
            if draft.steps.isEmpty {
                Text("No steps yet — add them here, or save now and add them later.").font(Theme.caption).foregroundStyle(Theme.muted)
            }
            ForEach($draft.steps) { $step in
                let number = (draft.steps.firstIndex { $0.id == step.id } ?? 0) + 1
                let doubtful = doubtfulSteps.contains(step.id)
                HStack(alignment: .top, spacing: 10) {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.green)
                        .frame(width: 24, height: 24)
                        .background(Theme.greenSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Describe this step", text: $step.text, axis: .vertical)
                            .font(.system(size: 15))
                            .focused($focused, equals: step.id)
                            .onChange(of: step.text) { _, _ in doubtfulSteps.remove(step.id) }
                        if doubtful { Text("Please check this step").font(Theme.micro).foregroundStyle(Theme.check) }
                    }
                    Button {
                        Haptics.destructive()
                        let id = step.id
                        withAnimation(Theme.snappy) { draft.steps.removeAll { $0.id == id } }
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Remove step \(number)")
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(doubtful ? Theme.check : Theme.line, lineWidth: doubtful ? 1.5 : 1))
            }
            Button {
                let step = DraftStep(text: "")
                withAnimation(Theme.snappy) { draft.steps.append(step) }
                focused = step.id
            } label: {
                Label("Add step", systemImage: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
            }
            .tint(Theme.green)
        }
    }

    private func nutritionCard(_ nutrition: DraftNutrition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nutrition estimate", systemImage: "chart.pie.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.green)
            Text("≈ \(Int(nutrition.calories)) kcal a serving · \(Int(nutrition.protein)) g protein · \(Int(nutrition.carbs)) g carbs · \(Int(nutrition.fat)) g fat")
                .font(Theme.caption).foregroundStyle(Theme.ink2)
            if nutrition.total > 0, nutrition.matched < nutrition.total {
                Text("Based on \(nutrition.matched) of \(nutrition.total) ingredients — the rest couldn't be matched.")
                    .font(Theme.micro).foregroundStyle(Theme.check)
            }
        }
        .card(padding: 14)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if checkCount > 0 {
                PrimaryButton(title: "Check later", tone: .outline) { save(checkLater: true) }
                    .frame(width: 130)
            }
            PrimaryButton(title: replaceDuplicate ? "Update recipe" : "Save recipe", systemImage: "checkmark",
                          isEnabled: !draft.title.trimmingCharacters(in: .whitespaces).isEmpty) { save(checkLater: false) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Logic

    private func timeFixed() {
        Haptics.step()
        if draft.prepMinutes + draft.cookMinutes > 0 { timeMissing = false }
    }

    /// Quick swaps for a problem ingredient that pass the household's rules.
    private func swaps(for item: DraftIngredient) -> [String] {
        SwapTable.options(for: item.name).compactMap { option in
            let amount = item.quantity.map {
                Amount.text(quantity: $0 * option.ratio, max: item.quantityMax.map { $0 * option.ratio }, unit: item.unit, system: settings.unitSystem)
            } ?? ""
            let line = [amount, option.name.lowercased()].filter { !$0.isEmpty }.joined(separator: " ")
            return FoodRules.check(ingredients: [line], profile: profile).isBlocked ? nil : line
        }
    }

    private func replace(_ id: UUID, with line: String) {
        guard let index = draft.ingredients.firstIndex(where: { $0.id == id }) else { return }
        var swapped = DraftIngredient(line: line)
        swapped.id = id
        withAnimation(Theme.snappy) { draft.ingredients[index] = swapped }
        doubtfulIngredients.remove(id)
        Haptics.success()
        DropsManager.showSuccess(title: "Swapped", subtitle: line)
    }

    private func save(checkLater: Bool) {
        let fields = RecipeDraftFields(title: draft.title, summary: draft.summary ?? "", cuisine: draft.cuisine ?? "", servings: draft.servings,
                                       minutes: draft.prepMinutes + draft.cookMinutes, tags: draft.tags,
                                       ingredients: draft.ingredients.map(\.text), steps: draft.steps.map(\.text))
        if let problem = Validate.recipe(fields) {
            withAnimation(Theme.snappy) { showErrors = true }
            Haptics.error()
            DropsManager.showError(title: "Please fix this first", subtitle: problem)
            return
        }
        var final = draft
        final.title = final.title.trimmingCharacters(in: .whitespacesAndNewlines)
        final.ingredients = final.ingredients
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { originalTexts[$0.id] == $0.text ? $0 : DraftIngredient(line: $0.text.trimmingCharacters(in: .whitespaces)) }
        final.steps = final.steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if timeMissing == false, final.totalMinutes < final.prepMinutes + final.cookMinutes {
            final.totalMinutes = final.prepMinutes + final.cookMinutes
        }
        var flags: [ReviewFlag] = []
        if checkLater {
            if servingsGuessed { flags.append(ReviewFlag(field: "servings", message: "Servings were guessed")) }
            if timeMissing { flags.append(ReviewFlag(field: "time", message: "No cooking time given")) }
            for (index, item) in final.ingredients.enumerated() where doubtfulIngredients.contains(item.id) {
                flags.append(ReviewFlag(field: "ingredient:\(index)", message: "Check “\(item.displayLine)”"))
            }
            for (index, step) in final.steps.enumerated() where doubtfulSteps.contains(step.id) {
                flags.append(ReviewFlag(field: "step:\(index)", message: "Check step \(index + 1)"))
            }
        }
        final.flags = flags
        let saved = Kitchen.save(final, into: replaceDuplicate ? duplicate : nil, imageData: imageData)
        Haptics.success()
        DropsManager.showSuccess(title: replaceDuplicate ? "Recipe updated" : "Saved to your cookbook",
                                 subtitle: checkLater ? "Marked to check later" : saved.displayTitle)
        NotificationService.shared.reschedule()
        onDone(saved)
    }
}
