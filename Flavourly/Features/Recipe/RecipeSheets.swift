import CoreData
import SwiftUI

// MARK: - Swaps

/// Offline swaps so substitution works without a connection; AI adds more on request.
enum SwapTable {
    typealias Option = (name: String, ratio: Double, why: String)

    private static let groups: [(keys: [String], options: [Option])] = [
        (["heavy cream", "double cream", "whipping cream", "cream"], [
            ("Greek yogurt", 1, "Lighter and tangy — stir in off the heat so it doesn't split"),
            ("Coconut milk", 1, "Dairy-free and silky, slightly sweet"),
            ("Cashew cream", 1, "Dairy-free and rich — blend soaked cashews with water"),
        ]),
        (["coconut milk"], [("Cashew cream", 1, "Just as rich, less coconut flavour"), ("Evaporated milk", 1, "Creamy, but contains dairy")]),
        (["almond milk", "oat milk", "soy milk", "rice milk"], [("Oat milk", 1, "Neutral and nut-free"), ("Milk", 1, "Dairy")]),
        (["butter"], [("Olive oil", 0.75, "Dairy-free — best in savoury cooking"), ("Ghee", 1, "Nutty; still dairy but very low lactose"), ("Vegan butter", 1, "Swaps 1:1, even in baking")]),
        (["milk"], [("Oat milk", 1, "Dairy-free and neutral"), ("Soy milk", 1, "Closest protein to dairy milk")]),
        (["eggs", "egg"], [("Flax egg", 1, "1 tbsp ground flax + 3 tbsp water each; rest 5 minutes. Binds in baking"), ("Mashed banana", 1, "About ¼ cup each — sweet bakes only")]),
        (["spaghetti", "penne", "fusilli", "farfalle", "pappardelle", "linguine", "macaroni", "pasta", "noodles"], [
            ("Gluten-free pasta", 1, "Cook 1–2 minutes less and toss straight away"),
            ("Zucchini noodles", 1.5, "Low carb; cook for just 2 minutes"),
        ]),
        (["soy sauce"], [("Tamari", 1, "Usually gluten-free — check the label"), ("Coconut aminos", 1, "Soy-free and a little sweeter")]),
        (["parmesan", "parmigiano", "pecorino"], [("Nutritional yeast", 0.5, "Dairy-free with a cheesy flavour"), ("Grana Padano", 1, "Similar and often cheaper")]),
        (["chicken"], [("Paneer", 1, "Vegetarian; add near the end so it stays soft"), ("Firm tofu", 1, "Vegan; press it first for a better sear"), ("Chickpeas", 1, "Vegan and full of fibre")]),
        (["beef", "lamb", "mince", "pork"], [("Brown lentils", 1, "Vegan, hearty texture"), ("Mushrooms", 1, "Chop finely for a meaty bite"), ("Chicken", 1, "Leaner")]),
        (["salmon", "cod", "tuna", "fish", "prawns", "prawn", "shrimp"], [("Firm tofu", 1, "Vegan; marinate for flavour"), ("Chicken thigh", 1, "Cook through fully"), ("Chickpeas", 1, "Vegan")]),
        (["peanut butter"], [("Sunflower seed butter", 1, "Peanut- and tree-nut-free"), ("Tahini", 1, "Contains sesame")]),
        (["peanuts", "peanut"], [("Sunflower seeds", 1, "Nut-free crunch"), ("Roasted chickpeas", 1, "Nut-free and higher in fibre")]),
        (["almonds", "almond", "cashews", "cashew", "walnuts", "walnut", "pecans", "pine nuts"], [("Pumpkin seeds", 1, "Nut-free crunch"), ("Sunflower seeds", 1, "Nut-free, mild flavour")]),
        (["plain flour", "all purpose flour", "maida", "flour"], [("Gluten-free flour blend", 1, "Choose one with xanthan gum for baking"), ("Oat flour", 1.25, "Use certified gluten-free oats if needed")]),
        (["breadcrumbs", "panko"], [("Gluten-free breadcrumbs", 1, "Swaps 1:1"), ("Crushed cornflakes", 1, "Extra crunchy")]),
        (["tahini"], [("Sunflower seed butter", 1, "Sesame-free"), ("Greek yogurt", 1, "Sesame-free, lighter")]),
        (["onion", "onions", "shallot"], [("Asafoetida", 0.02, "A pinch gives savoury depth in Jain and no-onion cooking"), ("Fennel", 1, "Similar crunch, mild")]),
        (["garlic"], [("Asafoetida", 0.1, "A pinch in hot oil gives a garlicky note"), ("Ginger", 1, "Different, but keeps the warmth")]),
        (["sugar"], [("Honey", 0.75, "Sweeter — reduce other liquids a little"), ("Jaggery", 1, "Caramel notes")]),
        (["greek yogurt", "yogurt", "yoghurt", "curd"], [("Coconut yogurt", 1, "Dairy-free"), ("Silken tofu", 1, "Vegan and high protein — blend smooth")]),
        (["mozzarella", "cheddar", "cheese", "feta", "ricotta"], [("Vegan cheese", 1, "Dairy-free"), ("Nutritional yeast", 0.3, "Dairy-free, cheesy flavour")]),
        (["paneer"], [("Firm tofu", 1, "Vegan; press first"), ("Halloumi", 1, "Holds its shape, saltier")]),
        (["basmati rice", "rice"], [("Cauliflower rice", 1, "Low carb, cooks in 5 minutes"), ("Quinoa", 1, "More protein")]),
        (["fish sauce"], [("Soy sauce", 1, "Fish-free"), ("Coconut aminos", 1, "Fish- and soy-free")]),
        (["mustard"], [("Horseradish", 0.5, "Mustard-free heat")]),
        (["white wine", "red wine", "wine"], [("Stock", 1, "Add a splash of vinegar for the acidity")]),
        (["lemon juice", "lemon"], [("Lime", 1, "Near-identical acidity"), ("White wine vinegar", 0.5, "Sharper — add a little at a time")]),
        (["chilli", "chili", "jalapeno", "cayenne", "red pepper flakes"], [("Sweet paprika", 1, "All the colour, none of the heat")]),
        (["mayonnaise", "mayo"], [("Greek yogurt", 1, "Lighter, egg-free"), ("Vegan mayo", 1, "Egg-free, swaps 1:1")]),
        (["bread", "wrap", "tortilla", "pita"], [("Gluten-free wrap", 1, "Warm it first so it doesn't crack"), ("Lettuce leaves", 1, "Low carb and gluten-free")]),
    ]

    static func options(for name: String) -> [Option] {
        let text = " " + FoodText.normalize(name) + " "
        var best: (length: Int, options: [Option])?
        for group in groups {
            for key in group.keys where text.contains(" " + FoodText.normalize(key) + " ") && key.count > (best?.length ?? 0) {
                best = (key.count, group.options)
            }
        }
        return best?.options.filter { FoodText.key($0.name) != FoodText.key(name) } ?? []
    }
}

struct SubstituteSheet: View {
    @ObservedObject var recipe: Recipe
    let ingredient: RecipeIngredient
    @Binding var swaps: [UUID: String]
    var scale: Double = 1

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var aiOptions: [SubstituteOption] = []
    @State private var loading = false
    @State private var saveToRecipe = false
    @State private var showPaywall = false
    @State private var showUnsafe = false

    private struct Checked: Identifiable {
        let option: SubstituteOption
        let line: String
        let result: FoodCheckResult
        let isAI: Bool
        var id: String { (isAI ? "ai|" : "") + option.id }
    }

    private var name: String { ingredient.name ?? "" }
    private var profile: FoodProfile { People.profile() }

    private var localOptions: [SubstituteOption] {
        SwapTable.options(for: name).map { option in
            let amount = ingredient.quantity > 0
                ? Amount.text(quantity: ingredient.quantity * option.ratio, max: ingredient.quantityMax > 0 ? ingredient.quantityMax * option.ratio : nil,
                              unit: ingredient.unit ?? "", system: settings.unitSystem)
                : ""
            return SubstituteOption(name: option.name.lowercased(), amount: amount, why: option.why)
        }
    }

    private var checked: [Checked] {
        var seen = Set<String>()
        let all = localOptions.map { ($0, false) } + aiOptions.map { ($0, true) }
        return all.compactMap { option, isAI in
            guard seen.insert(FoodText.key(option.name)).inserted else { return nil }
            let line = Self.line(option, scale: scale, system: settings.unitSystem)
            return Checked(option: option, line: line, result: FoodRules.check(ingredients: [line], profile: profile), isAI: isAI)
        }
    }

    var body: some View {
        let options = checked
        let safe = options.filter { !$0.result.isBlocked }
        let unsafe = options.filter(\.result.isBlocked)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SheetHeader(title: "Swap \(name)", subtitle: "Every option is checked against your household's rules") { dismiss() }

                    HStack(spacing: 12) {
                        IngredientIcon(name: name, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.amount(system: settings.unitSystem, scale: scale) + " " + name).font(Theme.rowTitle)
                            let issues = FoodRules.check(ingredients: [ingredient.checkLine], profile: profile).issues
                            Text(issues.first?.reason ?? "In \(recipe.displayTitle)")
                                .font(Theme.micro)
                                .foregroundStyle(issues.isEmpty ? Theme.muted : Theme.allergen)
                        }
                    }
                    .card(padding: 12)

                    if safe.isEmpty && !loading {
                        Text("No quick swaps for this one yet — ask AI below, or leave it out.")
                            .font(Theme.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(safe) { item in optionRow(item) }

                    if !unsafe.isEmpty {
                        DisclosureGroup(isExpanded: $showUnsafe) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(unsafe) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.option.name.capitalizedFirst).font(.system(size: 14, weight: .semibold)).strikethrough()
                                        Text(item.result.issues.first?.reason ?? "").font(Theme.micro).foregroundStyle(Theme.allergen)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Label("\(unsafe.count) hidden — not safe for your household", systemImage: "eye.slash")
                                .font(Theme.caption).foregroundStyle(Theme.muted)
                        }
                        .tint(Theme.muted)
                    }

                    aiButton

                    Toggle(isOn: $saveToRecipe) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save the swap to my recipe").font(.system(size: 15, weight: .medium))
                            Text(saveToRecipe ? "Your recipe is updated for every future cook" : "Just for this cook — the recipe stays as it is")
                                .font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.green)
                    .onChange(of: saveToRecipe) { _, _ in Haptics.toggle() }

                    Button(role: .destructive) {
                        apply(nil)
                    } label: {
                        Label(ingredient.isOptional ? "Leave it out (it's optional)" : "Leave it out", systemImage: "minus.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .tint(Theme.allergen)

                    if let id = ingredient.uuid, swaps[id] != nil {
                        Button {
                            swaps[id] = nil
                            Haptics.tick()
                            dismiss()
                        } label: {
                            Label("Undo swap", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .tint(Theme.ink2)
                    }
                }
                .padding(20)
            }
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showPaywall) { PaywallScreenView().environmentObject(settings) }
    }

    private func optionRow(_ item: Checked) -> some View {
        Button {
            apply(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IngredientIcon(name: item.option.name, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.line).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        if item.isAI { Badge(text: "AI", systemImage: "sparkles", tone: .purple) }
                    }
                    Text(item.option.why).font(Theme.micro).foregroundStyle(Theme.ink2).multilineTextAlignment(.leading)
                    if item.result.needsCheck, let reason = item.result.issues.first?.reason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill").font(Theme.micro).foregroundStyle(Theme.check)
                    } else if !profile.isEmpty {
                        Label("Fits your rules", systemImage: "checkmark.shield.fill").font(Theme.micro).foregroundStyle(Theme.green)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.green)
            }
            .card(padding: 12)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    @ViewBuilder
    private var aiButton: some View {
        let remaining = Usage.remaining(.aiSwap)
        if remaining > 0 {
            PrimaryButton(title: aiOptions.isEmpty ? "Ask AI for more ideas" : "Ask AI again",
                          systemImage: "sparkles", tone: .ai, isLoading: loading, height: 48) { askAI() }
            if !settings.isPremium {
                Text("\(remaining) free AI swaps left this week").font(Theme.micro).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                Text("You've used this week's free AI swaps. Quick swaps above always stay free.")
                    .font(Theme.micro).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                PrimaryButton(title: "Unlock unlimited AI", systemImage: "crown.fill", tone: .premium, height: 46) { showPaywall = true }
            }
        }
    }

    private func askAI() {
        loading = true
        Task {
            defer { loading = false }
            do {
                let options = try await AIService.substitutes(for: ingredient.checkLine, in: recipe)
                withAnimation(Theme.spring) { aiOptions = options }
                Haptics.success()
                if options.isEmpty { DropsManager.showInfo(title: "No new ideas", subtitle: "Try leaving it out or a quick swap") }
            } catch APIError.limit(let message) {
                Usage.exhaust(.aiSwap)
                DropsManager.showWarning(title: "Weekly limit reached", subtitle: message)
            } catch {
                DropsManager.showError(title: "Couldn't reach AI", subtitle: "Quick swaps still work offline")
            }
        }
    }

    /// nil = leave the ingredient out.
    private func apply(_ item: Checked?) {
        guard let id = ingredient.uuid else { return }
        if saveToRecipe {
            let target = Kitchen.adopt(recipe)
            guard let row = target.sortedIngredients.first(where: { $0.position == ingredient.position }) else { return }
            if let item {
                let parsed = IngredientParser.parse(Self.line(item.option, scale: 1, system: settings.unitSystem))
                row.substitutedFrom = row.substitutedFrom ?? row.name
                row.quantity = parsed.quantity ?? 0
                row.quantityMax = parsed.quantityMax ?? 0
                row.unit = parsed.unit
                row.name = parsed.name.isEmpty ? item.option.name : parsed.name
                row.note = nil
                row.originalText = parsed.original
                row.aisle = Aisle.classify(row.name ?? "").rawValue
                row.confidence = 1
            } else {
                Kitchen.context.delete(row)
            }
            target.updatedAt = .now
            Kitchen.save()
            Task { await Kitchen.refreshNutrition(target) }
            swaps[id] = nil
            DropsManager.showSuccess(title: item == nil ? "Removed from your recipe" : "Recipe updated", subtitle: item?.option.name.capitalizedFirst)
        } else {
            swaps[id] = item?.line ?? ""
            Haptics.success()
            DropsManager.showSuccess(title: item == nil ? "Left out for this cook" : "Swapped for this cook", subtitle: item?.line)
        }
        dismiss()
    }

    /// "150 ml oat milk" at the given scale; falls back to the name alone when there's no amount.
    static func line(_ option: SubstituteOption, scale: Double, system: UnitSystem) -> String {
        let text = "\(option.amount) \(option.name)".trimmingCharacters(in: .whitespaces)
        let parsed = IngredientParser.parse(text)
        guard let quantity = parsed.quantity else { return text }
        let amount = Amount.text(quantity: quantity, max: parsed.quantityMax, unit: parsed.unit, system: system, scale: scale)
        return "\(amount) \(parsed.name.isEmpty ? option.name : parsed.name)"
    }
}

// MARK: - Add to plan

struct AddToPlanSheet: View {
    @ObservedObject var recipe: Recipe
    var initialDay: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var day = Kitchen.calendar.startOfDay(for: .now)
    @State private var slot: MealSlot = .dinner
    @State private var eaters: [String] = []
    @State private var servings = 2
    @State private var servingsEdited = false
    @State private var leftovers = false
    @State private var leftoverDay = Kitchen.calendar.startOfDay(for: .now)
    @State private var leftoverSlot: MealSlot = .lunch
    @State private var didLoad = false

    private let people = People.all()
    private var days: [Date] { Kitchen.days(from: .now, count: 14) }
    private var check: FoodCheckResult { FoodRules.check(ingredients: recipe.checkLines, profile: People.profile(for: eaters)) }
    private var existing: [PlannedMeal] { Kitchen.meals(from: day, days: 1).filter { $0.mealSlot == slot } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SheetHeader(title: "Add to plan", subtitle: recipe.displayTitle) { dismiss() }

                    section("Day") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(days, id: \.self) { date in dayChip(date) }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }

                    section("Meal") {
                        Picker("Meal", selection: $slot) {
                            ForEach(MealSlot.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if !existing.isEmpty {
                            Text("Adds alongside \(existing.map(\.title).joined(separator: ", "))")
                                .font(Theme.micro).foregroundStyle(Theme.muted)
                        }
                    }

                    section("Who's eating") {
                        FlowLayout(spacing: 8) {
                            ForEach(people) { person in
                                let isOn = eaters.contains(person.id)
                                Button {
                                    Haptics.toggle()
                                    if isOn { eaters.removeAll { $0 == person.id } } else { eaters.append(person.id) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Avatar(initial: person.initial, color: person.color, size: 24)
                                        Text(person.isMe ? "You" : person.name).font(.system(size: 14, weight: .medium))
                                        if isOn { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                                    }
                                    .foregroundStyle(isOn ? Theme.green : Theme.ink2)
                                    .padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 5)
                                    .background(isOn ? Theme.greenSoft : .white, in: Capsule())
                                    .overlay(Capsule().strokeBorder(isOn ? Theme.green.opacity(0.4) : Theme.line))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                        safety
                    }

                    section("Servings") {
                        HStack {
                            StepperPill(value: Binding(get: { servings }, set: { servings = $0; servingsEdited = true }), range: 1...40)
                            Spacer()
                            if servingsEdited {
                                Button("Match who's eating") {
                                    servingsEdited = false
                                    servings = People.servings(for: eaters)
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .tint(Theme.green)
                            } else {
                                Text("Based on portions").font(Theme.micro).foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $leftovers.animation(Theme.spring)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cook extra for leftovers").font(.system(size: 15, weight: .medium))
                                Text("Adds a leftovers meal and scales your shopping").font(Theme.micro).foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.green)
                        .onChange(of: leftovers) { _, _ in Haptics.toggle() }
                        if leftovers {
                            HStack {
                                Picker("Leftover day", selection: $leftoverDay) {
                                    ForEach(days.filter { $0 >= day }, id: \.self) { Text($0.formatted(.dateTime.weekday(.abbreviated).day())).tag($0) }
                                }
                                Picker("Leftover meal", selection: $leftoverSlot) {
                                    ForEach(MealSlot.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                                }
                            }
                            .tint(Theme.green)
                        }
                    }
                    .card(padding: 14)

                    PrimaryButton(title: check.isBlocked ? "Add anyway" : "Add to \(day.formatted(.dateTime.weekday(.wide))) \(slot.label.lowercased())",
                                  systemImage: "calendar.badge.plus", tone: check.isBlocked ? .outline : .green, isEnabled: !eaters.isEmpty) { add() }
                }
                .padding(20)
            }
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
        .onChange(of: slot) { _, value in
            Haptics.select()
            eaters = People.defaultEaters(for: value)
        }
        .onChange(of: eaters) { _, value in if !servingsEdited { servings = People.servings(for: value) } }
        .onChange(of: day) { _, value in
            if leftoverDay <= value { leftoverDay = Kitchen.calendar.date(byAdding: .day, value: 1, to: value) ?? value }
        }
    }

    @ViewBuilder
    private var safety: some View {
        let result = check
        if result.isBlocked {
            Label(result.issues.first { $0.severity == .blocked }?.reason ?? "Not safe for someone eating", systemImage: "exclamationmark.shield.fill")
                .font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.allergen)
        } else if result.needsCheck {
            Label(result.issues.first?.reason ?? "Please check", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.micro).foregroundStyle(Theme.check)
        } else if eaters.count > 0 {
            Label("Safe for everyone eating", systemImage: "checkmark.shield.fill").font(Theme.micro).foregroundStyle(Theme.green)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func dayChip(_ date: Date) -> some View {
        let isOn = Kitchen.calendar.isDate(date, inSameDayAs: day)
        let planned = !Kitchen.meals(from: date, days: 1).filter { $0.mealSlot == slot }.isEmpty
        return Button {
            Haptics.select()
            withAnimation(Theme.snappy) { day = date }
        } label: {
            VStack(spacing: 3) {
                Text(Kitchen.calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 11, weight: .semibold))
                Text(date.formatted(.dateTime.day())).font(.system(size: 18, weight: .bold))
                Circle().fill(planned ? (isOn ? .white : Theme.plan) : .clear).frame(width: 5, height: 5)
            }
            .foregroundStyle(isOn ? .white : Theme.ink)
            .frame(width: 54, height: 66)
            .background(isOn ? AnyShapeStyle(Theme.greenGradient) : AnyShapeStyle(Color.white), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isOn ? .clear : Theme.line))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (planned ? ", already has a \(slot.label.lowercased())" : ""))
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let initialDay { day = Kitchen.calendar.startOfDay(for: initialDay) }
        let slots = recipe.slots
        slot = slots.contains(.dinner) ? .dinner : (slots.min() ?? .dinner)
        eaters = People.defaultEaters(for: slot)
        servings = People.servings(for: eaters)
        leftoverDay = Kitchen.calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }

    private func add() {
        let meal = Kitchen.plan(recipe, day: day, slot: slot, servings: servings, eaters: eaters)
        if leftovers {
            let leftoverEaters = People.defaultEaters(for: leftoverSlot)
            Kitchen.plan(recipe, day: leftoverDay, slot: leftoverSlot, servings: People.servings(for: leftoverEaters),
                         eaters: leftoverEaters, leftoverOf: meal)
        }
        DropsManager.showSuccess(title: "Added to \(day.formatted(.dateTime.weekday(.wide)))",
                                 subtitle: leftovers ? "Plus leftovers on \(leftoverDay.formatted(.dateTime.weekday(.wide)))" : recipe.displayTitle)
        dismiss()
    }
}
