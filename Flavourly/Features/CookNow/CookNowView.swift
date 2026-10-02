import CoreData
import SwiftUI
internal import Combine

/// Lets Home pre-answer "How much time do you have?" before the flame sheet opens.
@MainActor
final class CookNowModel: ObservableObject {
    static let shared = CookNowModel()
    @Published var minutes: Int?
}

/// What the user told Cook Now; drives both local ranking and AI ideas.
struct CookNowAnswers: Equatable {
    var minutes: Int? = 30
    var craving = ""
    var slot: MealSlot = .at(hour: Calendar.current.component(.hour, from: .now))
    var have: [String] = []
    /// 0 = only what I have, 2 = can buy a couple of things, nil = happy to shop.
    var okToBuy: Int? = 2
    var eaters: [String] = []
}

/// The flame button: four quick questions, then ideas that fit time, cravings, kitchen and everyone eating.
struct CookNowView: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var local = LocalFood.shared
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "expiresAt", ascending: true)]) private var pantry: FetchedResults<PantryItem>

    @State private var step = 0
    @State private var answers = CookNowAnswers()
    @State private var newItem = ""
    @State private var itemError: String?
    @State private var didLoad = false
    @FocusState private var typing: Bool

    private let questions = ["Time", "Craving", "Kitchen", "Who's eating"]
    /// What people in the cook's country crave (from the local catalogue), then universal moods.
    private var cravings: [String] { Array(local.cravings.prefix(14)) }
    /// Everyday staples of the cook's country that aren't ticked yet — one tap to add.
    private var staples: [String] {
        let have = Set(allItems.map { $0.lowercased() })
        return local.staples.filter { !have.contains($0.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if step < questions.count {
                    ScrollView {
                        Group {
                            switch step {
                            case 0: timeStep
                            case 1: cravingStep
                            case 2: kitchenStep
                            default: eatersStep
                            }
                        }
                        .padding(20)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                        .id(step)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    footer
                } else {
                    ScrollView {
                        CookNowResults(answers: answers) { withAnimation(Theme.spring) { step = 0 } }
                            .padding(20)
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(alignment: .top) {
                LinearGradient(colors: [Color(hex: "#FFE9DC"), Theme.canvas], startPoint: .top, endPoint: .center).ignoresSafeArea()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .flavourlyDestinations()
        }
        .animation(Theme.spring, value: step)
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                if step > 0 {
                    IconButton(systemImage: "chevron.left", label: "Back", style: .bordered) { step -= 1 }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.flameGradient, in: Circle())
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: step == questions.count)
                    Text("Cook Now").font(Theme.brand(22))
                }
                Spacer()
                IconButton(systemImage: "xmark", label: "Close", style: .bordered) { dismiss() }
            }
            if step < questions.count {
                HStack(spacing: 6) {
                    ForEach(questions.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Theme.line))
                            .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Question \(step + 1) of \(questions.count)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 && step < questions.count - 1 {
                PrimaryButton(title: "Skip", tone: .plain) { next() }.frame(width: 90)
            }
            PrimaryButton(title: step == questions.count - 1 ? "Show me ideas" : "Next",
                          systemImage: step == questions.count - 1 ? "sparkles" : "arrow.right",
                          tone: .flame, isEnabled: step != questions.count - 1 || !answers.eaters.isEmpty) { next() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func question(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.display(30)).foregroundStyle(Theme.ink)
            Text(subtitle).font(Theme.body).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Steps

    private var timeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            question("How much time do you have?", "We'll only show what fits.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                timeTile(15, "Something quick", "hare.fill")
                timeTile(30, "A proper meal", "fork.knife")
                timeTile(45, "Take it easy", "cup.and.saucer.fill")
                timeTile(nil, "No rush", "clock.fill")
            }
        }
    }

    private func timeTile(_ minutes: Int?, _ caption: String, _ symbol: String) -> some View {
        let isOn = answers.minutes == minutes
        return Button {
            Haptics.select()
            answers.minutes = minutes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if step == 0 { next() } }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn ? .white : Theme.capture)
                Text(minutes.map { "\($0) min" } ?? "1 hr +").font(.system(size: 22, weight: .bold))
                Text(caption).font(Theme.micro).opacity(0.85)
            }
            .foregroundStyle(isOn ? .white : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(isOn ? AnyShapeStyle(Theme.flameTextGradient) : AnyShapeStyle(Color.white),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(isOn ? .clear : Theme.line))
            .scaleEffect(isOn ? 1.02 : 1)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var cravingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            question("Craving anything?", "A dish, an ingredient or a mood — or skip it.")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("e.g. \(cravings.first?.lowercased() ?? "soup"), something light", text: $answers.craving)
                    .focused($typing)
                    .submitLabel(.next)
                    .onSubmit(next)
                if !answers.craving.isEmpty {
                    Button { answers.craving = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .accessibilityLabel("Clear")
                }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(typing ? Theme.capture : Theme.line, lineWidth: typing ? 1.5 : 1))
            FieldError(message: Validate.optional(answers.craving, field: "Craving", max: Validate.Limit.craving).message)
            FlowLayout(spacing: 8) {
                ForEach(cravings, id: \.self) { item in
                    Chip(title: item, isOn: answers.craving.caseInsensitiveCompare(item) == .orderedSame, style: .outline, small: true) {
                        answers.craving = answers.craving.caseInsensitiveCompare(item) == .orderedSame ? "" : item
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("FOR").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                Picker("Meal", selection: $answers.slot) {
                    ForEach(MealSlot.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: answers.slot) { _, slot in
                    Haptics.select()
                    answers.eaters = People.defaultEaters(for: slot)
                }
            }
        }
    }

    private var kitchenStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            question("What's in your kitchen?", "Untick anything you've run out of.")
            if pantry.isEmpty && answers.have.isEmpty {
                Text("Your pantry is empty — type a few things you have, or skip this.")
                    .font(Theme.caption).foregroundStyle(Theme.muted)
            }
            FlowLayout(spacing: 8) {
                ForEach(allItems, id: \.self) { name in
                    let isOn = answers.have.contains(name)
                    let soon = pantry.first { $0.displayName == name }.flatMap(\.daysLeft).map { $0 <= 3 } ?? false
                    Button {
                        Haptics.toggle()
                        if isOn { answers.have.removeAll { $0 == name } } else { answers.have.append(name) }
                    } label: {
                        HStack(spacing: 6) {
                            IngredientIcon(name: name, size: 22)
                            Text(name).font(.system(size: 14, weight: .medium))
                            if soon { Circle().fill(Theme.capture).frame(width: 6, height: 6).accessibilityLabel("use soon") }
                        }
                        .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 5)
                        .background(isOn ? Theme.pantrySoft : .white, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? Theme.pantry.opacity(0.5) : Theme.line))
                        .opacity(isOn ? 1 : 0.7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            if !staples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COMMON IN \(local.countryName.uppercased()) KITCHENS").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                    FlowLayout(spacing: 8) {
                        ForEach(staples, id: \.self) { name in
                            Button {
                                Haptics.toggle()
                                withAnimation(Theme.snappy) { answers.have.append(name) }
                            } label: {
                                HStack(spacing: 5) {
                                    IngredientIcon(name: name, size: 20)
                                    Text(name).font(.system(size: 13, weight: .medium))
                                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(Theme.ink2)
                                .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
                                .background(Theme.chip, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(name)")
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(Theme.pantry)
                TextField("Add what you have (e.g. eggs, rice)", text: $newItem)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { addItem() }
                    .onChange(of: newItem) { _, _ in itemError = nil }
                if !newItem.isEmpty { Button("Add") { addItem() }.font(.system(size: 14, weight: .semibold)).tint(Theme.pantry) }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(itemError != nil ? Theme.allergen : Theme.line))
            FieldError(message: itemError)

            VStack(alignment: .leading, spacing: 8) {
                Text("SHOPPING").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                Picker("Shopping", selection: $answers.okToBuy) {
                    Text("Only what I have").tag(Int?.some(0))
                    Text("Buy 1–2 things").tag(Int?.some(2))
                    Text("Happy to shop").tag(Int?.none)
                }
                .pickerStyle(.segmented)
                .onChange(of: answers.okToBuy) { _, _ in Haptics.select() }
            }
        }
    }

    private var eatersStep: some View {
        let people = People.all()
        return VStack(alignment: .leading, spacing: 18) {
            question("Who's eating?", "Everyone's allergies and diets are applied.")
            VStack(spacing: 10) {
                ForEach(people) { person in
                    let isOn = answers.eaters.contains(person.id)
                    Button {
                        Haptics.toggle()
                        if isOn { answers.eaters.removeAll { $0 == person.id } } else { answers.eaters.append(person.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(initial: person.initial, color: person.color, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.isMe ? "You" : person.name).font(Theme.rowTitle).foregroundStyle(Theme.ink)
                                let rules = person.allergies + person.diets
                                Text(rules.isEmpty ? "No food rules" : rules.prefix(3).joined(separator: " · "))
                                    .font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            CheckCircle(isOn: isOn, tint: Theme.capture)
                        }
                        .card(padding: 12)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isOn ? Theme.capture.opacity(0.5) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            if people.count == 1 {
                NavigationLink(value: Route.household) {
                    Label("Add family or housemates", systemImage: "person.badge.plus").font(.system(size: 14, weight: .semibold))
                }
                .tint(Theme.green)
            }
            if !answers.eaters.isEmpty {
                Text("Cooking \(plural(People.servings(for: answers.eaters), "serving"))").font(Theme.caption).foregroundStyle(Theme.ink2)
            }
        }
    }

    // MARK: Logic

    private var allItems: [String] {
        let stocked = pantry.map(\.displayName).filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: stocked + answers.have)) as? [String] ?? stocked
    }

    /// "eggs, rice" adds two items. Returns false (and shows why) when something isn't a food.
    @discardableResult
    private func addItem() -> Bool {
        let checked = Validate.items(newItem)
        if let message = checked.message {
            withAnimation(Theme.snappy) { itemError = message }
            Haptics.error()
            return false
        }
        for item in checked.items {
            let name = String(item.prefix(Validate.Limit.itemName)).capitalizedFirst
            if !answers.have.contains(name) { answers.have.append(name) }
        }
        newItem = ""
        Haptics.tick()
        return true
    }

    private func next() {
        typing = false
        if step == 1 {
            let craving = Validate.optional(answers.craving, field: "Craving", max: Validate.Limit.craving)
            guard craving.isValid else {
                Haptics.error()
                return
            }
            answers.craving = craving.value
        }
        if step == 2, !newItem.isEmpty, !addItem() { return }
        Haptics.primary()
        step += 1
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let preset = CookNowModel.shared.minutes {
            answers.minutes = preset >= 60 ? nil : preset
            CookNowModel.shared.minutes = nil
            step = 1
        }
        answers.have = pantry.map(\.displayName).filter { !$0.isEmpty }
        answers.eaters = People.defaultEaters(for: answers.slot)
    }
}

// MARK: - Results

struct CookNowResults: View {
    let answers: CookNowAnswers
    var onChange: (() -> Void)?

    @EnvironmentObject private var settings: SettingsManager
    @State private var ideas: [CookNowIdea] = []
    @State private var hidden = 0
    @State private var loading = false
    @State private var showPaywall = false
    @State private var relaxed = false

    private var context: RankContext {
        var context = RankContext()
        context.profile = People.profile(for: answers.eaters)
        context.maxMinutes = answers.minutes
        context.slot = answers.slot
        context.pantry = answers.have.map { PantrySignal(key: FoodText.key($0), name: $0, daysLeft: nil) } + useSoonSignals
        context.craving = answers.craving
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        context.maxMissing = relaxed ? nil : answers.okToBuy
        return context
    }

    /// Pantry items near expiry get a boost when they're ticked.
    private var useSoonSignals: [PantrySignal] {
        Kitchen.pantrySignals().filter { signal in (signal.daysLeft ?? 99) <= 3 && answers.have.contains(signal.name) }
    }

    private var ranked: [(Recipe, Ranked)] {
        let pool = Kitchen.candidates()
        let byKey = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return Recommender.rank(pool.map(\.facts), context).prefix(12).compactMap { rank in byKey[rank.id].map { ($0, rank) } }
    }

    var body: some View {
        let results = ranked
        VStack(alignment: .leading, spacing: 16) {
            summary
            if results.isEmpty {
                VStack(spacing: 12) {
                    EmptyStateView(systemImage: "frying.pan", title: "Nothing fits all of that",
                                   message: answers.okToBuy == 0 && !relaxed ? "Nothing uses only what you have." : "Try more time or a different craving.")
                    if answers.okToBuy != nil && !relaxed {
                        PrimaryButton(title: "Show ideas that need a few more things", tone: .outline, height: 46) {
                            withAnimation(Theme.spring) { relaxed = true }
                        }
                    }
                }
            } else {
                SectionHeader(title: "From your cookbook & library", subtitle: "\(results.count) fit — safest and closest first")
                ForEach(results, id: \.1.id) { recipe, rank in CookNowRow(recipe: recipe, rank: rank) }
            }
            aiSection
        }
        .sheet(isPresented: $showPaywall) { PaywallScreenView().environmentObject(settings) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(answers.craving.isEmpty ? "Here's what you can cook" : "Ideas for \u{201C}\(answers.craving)\u{201D}")
                .font(Theme.display(28))
            FlowLayout(spacing: 6) {
                Badge(text: answers.minutes.map { "≤ \($0) min" } ?? "Any time", systemImage: "clock", tone: .orange)
                Badge(text: answers.slot.label, systemImage: answers.slot.symbol, tone: .neutral)
                Badge(text: answers.okToBuy == 0 && !relaxed ? "Only what I have" : (answers.okToBuy == 2 && !relaxed ? "Buy ≤ 2 things" : "Shopping OK"),
                      systemImage: "basket", tone: .teal)
                Badge(text: plural(People.servings(for: answers.eaters), "serving"), systemImage: "person.2", tone: .neutral)
                let allergens = People.profile(for: answers.eaters).allergenSummary
                if !allergens.isEmpty { Badge(text: "No \(allergens)", systemImage: "checkmark.shield.fill", tone: .green) }
            }
            if let onChange {
                Button("Change answers", action: onChange).font(.system(size: 14, weight: .semibold)).tint(Theme.capture)
            }
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.ai)
                Text("Fresh ideas with AI").font(Theme.section)
            }
            Text("New recipes built around what you have. Every idea is re-checked against everyone's allergies before you see it.")
                .font(Theme.micro).foregroundStyle(Theme.muted)
            ForEach(ideas) { idea in AIIdeaCard(idea: idea) }
            if hidden > 0 {
                Label("\(hidden) ideas hidden — not safe for someone eating", systemImage: "eye.slash")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
            }
            if Usage.canUse(.aiIdeas) {
                PrimaryButton(title: ideas.isEmpty ? "Get 3 AI ideas" : "More ideas", systemImage: "sparkles", tone: .ai,
                              isLoading: loading, height: 48) { askAI() }
                if !settings.isPremium {
                    Text("\(Usage.remaining(.aiIdeas)) free AI idea requests left this week").font(Theme.micro).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            } else {
                PrimaryButton(title: "Unlock unlimited AI ideas", systemImage: "crown.fill", tone: .premium, height: 46) { showPaywall = true }
            }
        }
        .padding(16)
        .background(Theme.aiWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func askAI() {
        loading = true
        let request = AIService.CookNowRequest(
            minutes: answers.minutes, craving: answers.craving, pantry: answers.have, okToBuy: answers.okToBuy ?? 5,
            servings: People.servings(for: answers.eaters), rules: .current(for: answers.eaters),
            avoidTitles: ranked.prefix(6).map { $0.0.displayTitle } + ideas.map(\.recipe.title),
            country: LocalFood.shared.country
        )
        Task {
            defer { loading = false }
            do {
                let fresh = try await AIService.cookNowIdeas(request)
                let profile = People.profile(for: answers.eaters)
                let safe = fresh.filter { idea in
                    !FoodRules.check(ingredients: idea.recipe.ingredients.map { $0.text.isEmpty ? $0.displayLine : $0.text }, profile: profile).isBlocked
                }
                hidden += fresh.count - safe.count
                withAnimation(Theme.spring) { ideas += safe }
                safe.isEmpty ? Haptics.warning() : Haptics.success()
            } catch APIError.limit(let message) {
                Usage.exhaust(.aiIdeas)
                DropsManager.showWarning(title: "Weekly limit reached", subtitle: message)
            } catch {
                DropsManager.showError(title: "Couldn't get AI ideas", subtitle: error.localizedDescription)
            }
        }
    }
}

private struct CookNowRow: View {
    @ObservedObject var recipe: Recipe
    let rank: Ranked

    var body: some View {
        NavigationLink(value: recipe.route) {
            HStack(spacing: 12) {
                RecipeImage(recipe: recipe, cornerRadius: 16).frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.displayTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if recipe.minutes > 0 { Label("\(recipe.minutes) min", systemImage: "clock") }
                        if recipe.calories > 0 { Text("· \(Int(recipe.calories)) kcal") }
                    }
                    .font(Theme.micro).foregroundStyle(Theme.muted)
                    if !rank.have.isEmpty || !rank.missing.isEmpty {
                        HStack(spacing: 4) {
                            Badge(text: "Have \(rank.have.count)/\(rank.have.count + rank.missing.count)", tone: .teal)
                            if !rank.missing.isEmpty {
                                Text("Buy: " + rank.missing.prefix(2).joined(separator: ", ").lowercased() + (rank.missing.count > 2 ? "…" : ""))
                                    .font(Theme.micro).foregroundStyle(Theme.ink2).lineLimit(1)
                            }
                        }
                    }
                    if let reason = rank.reasons.first(where: { !$0.hasPrefix("Ready in") }) {
                        Text(reason).font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.green).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .card(padding: 10)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

private struct AIIdeaCard: View {
    let idea: CookNowIdea
    @State private var saved: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(idea.recipe.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text([idea.recipe.minutes > 0 ? "\(idea.recipe.minutes) min" : nil,
                          idea.recipe.nutrition.map { "\(Int($0.calories)) kcal" },
                          "\(idea.recipe.ingredients.count) ingredients"].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.micro).foregroundStyle(Theme.muted)
                }
                Spacer()
                Badge(text: "AI", systemImage: "sparkles", tone: .purple)
            }
            if let reason = idea.reason { Text(reason).font(Theme.caption).foregroundStyle(Theme.ink2) }
            Text(idea.recipe.ingredients.prefix(6).map(\.name).joined(separator: ", "))
                .font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(2)
            if let saved {
                NavigationLink(value: saved.route) {
                    Label("Open recipe", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(Theme.greenGradient, in: Capsule())
                }
            } else {
                PrimaryButton(title: "Save & open", systemImage: "bookmark.fill", tone: .soft, height: 44) {
                    var draft = idea.recipe
                    draft.method = "ai"
                    draft.tags = Array(Set(draft.tags + ["AI idea"]))
                    draft.flags = []
                    saved = Kitchen.save(draft)
                    DropsManager.showSuccess(title: "Saved to your cookbook", subtitle: draft.title)
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ai.opacity(0.25)))
    }
}

// MARK: - Cook from pantry

/// "What can I cook?" from Home's Use-soon strip and the Pantry screen.
struct CookFromPantryView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "expiresAt", ascending: true)]) private var pantry: FetchedResults<PantryItem>

    var body: some View {
        ScrollView {
            if pantry.isEmpty {
                EmptyStateView(systemImage: "cabinet", title: "Your pantry is empty",
                               message: "Add what you have in Shop › Pantry and we'll find recipes that use it.")
                    .padding(20)
            } else {
                CookNowResults(answers: CookNowAnswers(
                    minutes: nil, craving: "", slot: .at(hour: Calendar.current.component(.hour, from: .now)),
                    have: pantry.map(\.displayName), okToBuy: 2, eaters: People.defaultEaters(for: .dinner)
                ))
                .padding(20)
            }
        }
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("Cook from pantry")
        .navigationBarTitleDisplayMode(.inline)
    }
}
