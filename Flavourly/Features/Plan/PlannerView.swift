import SwiftUI

/// "Plan my week": fills only empty slots, never touches locked or existing meals.
/// AI (when allowed) chooses among candidates that already passed the household's hard rules;
/// every AI answer is validated again, and anything invalid falls back to the local planner.
struct PlannerView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var nextWeek = false
    @State private var slots: Set<MealSlot> = [.dinner]
    @State private var cookDays: Set<Int> = Set(1...7)
    @State private var weeknightMax: Int? = 30
    @State private var weekendMax: Int? = 60
    @State private var leftovers = true
    @State private var pantryFirst = true
    @State private var highProtein = false
    @State private var styles: Set<String> = []
    @State private var useAI = true
    @State private var working = false
    @State private var proposals: [Proposal]?
    @State private var skipped: Set<PlanSlot> = []
    @State private var showPaywall = false
    @State private var didLoad = false

    struct Proposal: Identifiable {
        var pick: PlanPick
        var recipe: Recipe
        var byAI: Bool
        var id: PlanSlot { pick.slot }
    }

    private static let styleOptions = ["Balanced", "Mediterranean", "High protein", "Low calorie", "Vegetarian", "Vegan", "Pescatarian",
                                       "Keto", "Low carb", "Gluten free", "Dairy free", "Low sodium", "Heart healthy", "Family friendly",
                                       "Budget friendly", "Meal prep", "Quick meals", "Plant forward"]
    private static let weekdays: [(Int, String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    private var weekStart: Date {
        let start = Kitchen.weekStart()
        return nextWeek ? Kitchen.calendar.date(byAdding: .day, value: 7, to: start) ?? start : start
    }

    /// Empty slots from today onwards; filled and locked slots are left alone.
    private var emptySlots: [PlanSlot] {
        let today = Kitchen.calendar.startOfDay(for: .now)
        let taken = Set(Kitchen.meals(from: weekStart).map { PlanSlot(day: Kitchen.calendar.startOfDay(for: $0.day ?? .now), slot: $0.mealSlot) })
        return Kitchen.days(from: weekStart).filter { $0 >= today }.flatMap { day in
            slots.sorted().map { PlanSlot(day: day, slot: $0) }
        }
        .filter { !taken.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let proposals {
                    review(proposals)
                } else {
                    setup
                }
            }
            .padding(20)
            .padding(.bottom, 20)
            .animation(Theme.spring, value: proposals == nil)
        }
        .dockSpacing()
        .background(alignment: .top) { Theme.aiWash.frame(height: 320).ignoresSafeArea() }
        .canvasBackground()
        .navigationTitle(proposals == nil ? "Plan my week" : "Your new plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallScreenView().environmentObject(settings) }
        .onAppear(perform: load)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Let's plan your week").font(Theme.display(30))
                Text("We only fill empty meals. Anything you've planned or locked stays exactly as it is.")
                    .font(Theme.caption).foregroundStyle(Theme.ink2)
            }

            card("Which week") {
                Picker("Week", selection: $nextWeek) {
                    Text("This week").tag(false)
                    Text("Next week").tag(true)
                }
                .pickerStyle(.segmented)
            }

            card("Meals to plan") {
                HStack(spacing: 6) {
                    ForEach(MealSlot.allCases) { slot in
                        Chip(title: slot.label, systemImage: slot.symbol, isOn: slots.contains(slot), style: .ai, small: true) {
                            if slots.contains(slot) { if slots.count > 1 { slots.remove(slot) } } else { slots.insert(slot) }
                        }
                    }
                }
            }

            card("Days you'll cook", footnote: "Other days get 15-minute meals or leftovers.") {
                HStack(spacing: 6) {
                    ForEach(Self.weekdays.indices, id: \.self) { index in
                        let (day, letter) = Self.weekdays[index]
                        let isOn = cookDays.contains(day)
                        Button {
                            Haptics.toggle()
                            if isOn { if cookDays.count > 1 { cookDays.remove(day) } } else { cookDays.insert(day) }
                        } label: {
                            Text(letter)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(isOn ? .white : Theme.ink2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(isOn ? AnyShapeStyle(Theme.aiGradient) : AnyShapeStyle(Theme.chip), in: Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel(Kitchen.calendar.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }

            card("Time limits") {
                timePicker("Weeknights", selection: $weeknightMax)
                timePicker("Weekends", selection: $weekendMax)
            }

            card("How to plan") {
                ToggleRow(title: "Leftovers for next-day lunch", subtitle: "Cooks extra at dinner and scales your list",
                          systemImage: "takeoutbag.and.cup.and.straw.fill", tint: Theme.pantry, isOn: $leftovers)
                ToggleRow(title: "Use my pantry first", subtitle: "Especially things that expire soon",
                          systemImage: "cabinet.fill", tint: Theme.pantry, isOn: $pantryFirst)
                ToggleRow(title: "Prioritise protein", subtitle: People.me().proteinTarget > 0 ? "Target \(People.me().proteinTarget) g a day" : nil,
                          systemImage: "dumbbell.fill", tint: Theme.plan, isOn: $highProtein)
            }

            card("Plan style", footnote: "Diet styles become hard rules for this plan; the rest guide the choice.") {
                FlowLayout(spacing: 6) {
                    ForEach(Self.styleOptions, id: \.self) { style in
                        Chip(title: style, isOn: styles.contains(style), style: .ai, small: true) {
                            if styles.contains(style) { styles.remove(style) } else { styles.insert(style) }
                        }
                    }
                }
            }

            rulesCard
            aiCard

            let count = emptySlots.count
            PrimaryButton(title: count == 0 ? "Nothing to plan" : "Create my plan · \(count) meal\(count == 1 ? "" : "s")",
                          systemImage: "sparkles", tone: .ai, isLoading: working, isEnabled: count > 0) {
                Task { await createPlan() }
            }
            if count == 0 {
                Text("Every chosen meal this week is already planned. Pick more meals or next week.")
                    .font(Theme.micro).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }
        }
    }

    private var rulesCard: some View {
        let profile = People.profile()
        let people = People.all()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 20)).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Always applied for \(people.count == 1 ? "you" : "all \(people.count) people")").font(.system(size: 14, weight: .semibold))
                Text(profile.isEmpty ? "No allergies or diets set." :
                        [profile.allergenSummary.isEmpty ? nil : "No \(profile.allergenSummary)",
                         profile.diets.isEmpty ? nil : profile.diets.keys.map(\.label).sorted().joined(separator: ", "),
                         profile.dislikes.isEmpty ? nil : "Skips \(profile.dislikes.keys.sorted().prefix(3).joined(separator: ", "))"]
                            .compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.micro).foregroundStyle(Theme.ink2)
                NavigationLink("Edit household & rules", value: Route.household).font(Theme.micro.weight(.semibold)).tint(Theme.green)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.greenTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var aiCard: some View {
        if Usage.canUse(.aiPlan) {
            ToggleRow(title: "Let AI choose", subtitle: settings.isPremium ? "Balances variety, time and your goals" :
                        "\(Usage.remaining(.aiPlan)) free AI plan left this week · works offline without it",
                      systemImage: "sparkles", tint: Theme.ai, isOn: $useAI)
                .card(padding: 8)
        } else {
            HStack(spacing: 12) {
                IconTile(systemImage: "sparkles", tint: Theme.ai, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart planning is on").font(.system(size: 14, weight: .semibold))
                    Text("This week's free AI plan is used — we'll plan with your rules and history instead.")
                        .font(Theme.micro).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button("Unlock") { showPaywall = true }.font(.system(size: 13, weight: .bold)).tint(Theme.premiumDeep)
            }
            .card(padding: 12)
        }
    }

    private func card<Content: View>(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
            content()
            if let footnote { Text(footnote).font(Theme.micro).foregroundStyle(Theme.muted) }
        }
        .card(padding: 14)
    }

    private func timePicker(_ title: String, selection: Binding<Int?>) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            Picker(title, selection: selection) {
                ForEach([15, 20, 30, 45, 60], id: \.self) { Text("≤ \($0) min").tag(Int?.some($0)) }
                Text("Any time").tag(Int?.none)
            }
            .tint(Theme.aiDeep)
        }
    }

    // MARK: Review

    private func review(_ items: [Proposal]) -> some View {
        let byDay = Dictionary(grouping: items) { $0.pick.slot.day }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(items.count - skipped.count) meals ready").font(Theme.display(30))
                Text("Untick anything you don't want. Tap ↻ to see another option.").font(Theme.caption).foregroundStyle(Theme.ink2)
                if items.contains(where: \.byAI) { Badge(text: "Chosen with AI · checked against your rules", systemImage: "sparkles", tone: .purple) }
            }
            ForEach(byDay.keys.sorted(), id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Kitchen.calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.system(size: 16, weight: .bold))
                    ForEach((byDay[day] ?? []).sorted { $0.pick.slot < $1.pick.slot }) { proposal in proposalRow(proposal) }
                }
            }
            PrimaryButton(title: "Add \(items.count - skipped.count) meals to my plan", systemImage: "checkmark", tone: .green,
                          isEnabled: items.count > skipped.count) { accept(items) }
            PrimaryButton(title: "Change settings", tone: .plain, height: 44) {
                withAnimation(Theme.spring) { proposals = nil }
            }
        }
    }

    private func proposalRow(_ proposal: Proposal) -> some View {
        let isOn = !skipped.contains(proposal.id) && !(proposal.pick.leftoverOf.map { skipped.contains($0) } ?? false)
        return HStack(spacing: 12) {
            Button {
                Haptics.toggle()
                if skipped.contains(proposal.id) { skipped.remove(proposal.id) } else { skipped.insert(proposal.id) }
            } label: {
                CheckCircle(isOn: isOn, tint: Theme.ai)
            }
            .accessibilityLabel(isOn ? "Included" : "Skipped")
            RecipeImage(recipe: proposal.recipe, cornerRadius: 12).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.pick.slot.slot.label.uppercased()).font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                Text(proposal.recipe.displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(proposal.pick.reason).font(Theme.micro).foregroundStyle(proposal.pick.leftoverOf == nil ? Theme.ink2 : Theme.pantry).lineLimit(2)
            }
            Spacer(minLength: 0)
            if proposal.pick.leftoverOf == nil {
                Button {
                    shuffle(proposal)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.aiDeep)
                        .frame(width: 36, height: 36).background(Theme.aiSoft, in: Circle())
                }
                .accessibilityLabel("Show another option")
            }
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isOn ? 1 : 0.5)
    }

    // MARK: Planning

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let prefs = settings.customizationPreferences
        let schedule = prefs.choices["schedule"] ?? []
        var chosen = Set<MealSlot>()
        if schedule.contains("Weekday breakfasts") { chosen.insert(.breakfast) }
        if schedule.contains("Weekday lunches") { chosen.insert(.lunch) }
        if schedule.contains("Weeknight dinners") || chosen.isEmpty { chosen.insert(.dinner) }
        if (prefs.choices["modes"] ?? []).contains("Snacks") { chosen.insert(.snack) }
        slots = chosen
        switch prefs.choices["frequency"]?.first {
        case "4–5 times a week": cookDays = [1, 2, 3, 4, 5]
        case "2–3 times a week": cookDays = [1, 2, 4]
        case "Once a week": cookDays = [1]
        case "Mostly meal prep": cookDays = [1, 4]
        default: cookDays = Set(1...7)
        }
        if let limit = prefs.choices["maxTime"]?.first {
            weeknightMax = Int(limit.prefix { $0.isNumber })
            weekendMax = weeknightMax.map { max($0, 45) }
        }
        let modes = prefs.choices["modes"] ?? []
        leftovers = modes.isEmpty || modes.contains("Leftovers") || modes.contains("Batch cooking")
        styles = Set(prefs.choices["planTypes"] ?? [])
        highProtein = People.me().wantsHighProtein || styles.contains("High protein")
        useAI = Usage.canUse(.aiPlan)
        let weekday = Kitchen.calendar.component(.weekday, from: .now)
        nextWeek = [6, 7, 1].contains(weekday)
    }

    private var options: PlannerOptions {
        var options = PlannerOptions()
        options.cookDays = cookDays
        options.leftoversForLunch = leftovers && slots.contains(.lunch)
        let quick = styles.contains("Quick meals")
        options.weeknightMax = quick ? min(weeknightMax ?? 20, 20) : weeknightMax
        options.weekendMax = quick ? min(weekendMax ?? 30, 30) : weekendMax
        let me = People.me()
        if me.calorieTarget > 0 { options.dailyCalories = Double(me.calorieTarget) }
        if me.proteinTarget > 0 { options.dailyProtein = Double(me.proteinTarget) }
        return options
    }

    private var baseContext: RankContext {
        var context = RankContext()
        var profile = People.profile()
        let diets = styles.compactMap { Diet(label: $0) }.map(\.label)
        if !diets.isEmpty { profile.add(person: "This plan", allergies: [], diets: diets, dislikes: [], mild: false) }
        context.profile = profile
        context.pantry = pantryFirst ? Kitchen.pantrySignals() : []
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = highProtein
        context.strictAllergens = true // nobody reviews an automatic plan dish by dish
        return context
    }

    private var pool: [Recipe] {
        var all = Kitchen.candidates()
        if styles.contains("Low calorie") { all = all.filter { $0.calories == 0 || $0.calories <= 550 } }
        // Budget friendly = the cheaper half of recipes whose cost is known from the cook's own prices;
        // recipes without a known cost stay in, so a new user still gets a full week.
        if styles.contains("Budget friendly") {
            let costs = all.compactMap { $0.costEstimate?.perServing }.sorted()
            if costs.count >= 4 {
                let median = costs[costs.count / 2]
                all = all.filter { ($0.costEstimate?.perServing ?? 0) <= median }
            }
        }
        return all
    }

    private func createPlan() async {
        working = true
        defer { working = false }
        let recipes = pool
        let byKey = Dictionary(recipes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let facts = recipes.map(\.facts)
        let empty = emptySlots
        var existing: [PlanSlot: String] = [:]
        for meal in Kitchen.meals(from: weekStart) {
            if let key = meal.recipe?.key { existing[PlanSlot(day: Kitchen.calendar.startOfDay(for: meal.day ?? .now), slot: meal.mealSlot)] = key }
        }

        var picks: [PlanPick] = []
        var aiSlots = Set<PlanSlot>()
        if useAI && Usage.canUse(.aiPlan) {
            DropsManager.showProgress(id: "plan", title: "Planning your week", fraction: 0.25, subtitle: "Choosing from recipes that fit your rules")
            do {
                let ai = try await aiPicks(empty: empty, facts: facts)
                picks = ai
                aiSlots = Set(ai.map(\.slot))
                DropsManager.showProgress(id: "plan", title: "Planning your week", fraction: 0.75, subtitle: "Checking every pick")
            } catch APIError.limit(let message) {
                Usage.exhaust(.aiPlan)
                DropsManager.endProgress(id: "plan")
                DropsManager.showInfo(title: "Planned without AI", subtitle: message)
            } catch {
                DropsManager.endProgress(id: "plan")
                DropsManager.showInfo(title: "Planned on your iPhone", subtitle: "AI wasn't reachable — your rules still apply")
            }
        }
        // Whatever AI didn't fill (or everything, offline) goes to the local planner.
        var known = existing
        for pick in picks { known[pick.slot] = pick.recipeID }
        let rest = empty.filter { !aiSlots.contains($0) }
        picks += Planner.fill(empty: rest, existing: known, recipes: facts, base: baseContext, options: options, calendar: Kitchen.calendar)

        let result = picks.sorted { $0.slot < $1.slot }.compactMap { pick -> Proposal? in
            guard let recipe = byKey[pick.recipeID] ?? Kitchen.recipe(forKey: pick.recipeID) else { return nil }
            return Proposal(pick: pick, recipe: recipe, byAI: aiSlots.contains(pick.slot))
        }
        DropsManager.endProgress(id: "plan")
        skipped = []
        if result.isEmpty {
            Haptics.warning()
            DropsManager.showWarning(title: "Nothing fits yet", subtitle: "Save a few more recipes or relax the time limits")
        } else {
            Haptics.success()
            withAnimation(Theme.spring) { proposals = result }
        }
    }

    /// Sends each slot's rule-safe shortlist; accepts only answers that come from that shortlist.
    private func aiPicks(empty: [PlanSlot], facts: [RecipeFacts]) async throws -> [PlanPick] {
        let formatter = DateFormatter()
        formatter.calendar = Kitchen.calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let plannerOptions = options
        // With leftovers on, lunches are left to the local planner so they can reuse the night before.
        let targets = empty.filter { !(plannerOptions.leftoversForLunch && $0.slot == .lunch) }
        guard !targets.isEmpty else { return [] }
        var shortlist: [PlanSlot: [String]] = [:]
        var used = Set<String>()
        var requests: [AIService.PlanSlotRequest] = []
        for slot in targets {
            var context = baseContext
            context.slot = slot.slot
            let weekday = Kitchen.calendar.component(.weekday, from: slot.day)
            let limit = weekday == 1 || weekday == 7 ? plannerOptions.weekendMax : plannerOptions.weeknightMax
            context.maxMinutes = plannerOptions.cookDays.contains(weekday) ? limit : min(limit ?? 15, 15)
            let ids = Recommender.rank(facts, context).prefix(12).map(\.id)
            guard !ids.isEmpty else { continue }
            shortlist[slot] = ids
            used.formUnion(ids)
            requests.append(.init(date: formatter.string(from: slot.day), slot: slot.slot.rawValue, candidates: ids))
        }
        guard !requests.isEmpty else { return [] }
        let candidates = facts.filter { used.contains($0.id) }.map { fact in
            AIService.PlanCandidate(id: fact.id, title: fact.title, minutes: fact.minutes, slots: fact.slots.map(\.rawValue),
                                    cuisine: fact.cuisine, protein: Int(fact.protein), reasons: [])
        }
        var preferences = Array(styles).sorted() + (settings.customizationPreferences.choices["goals"] ?? [])
        if highProtein { preferences.append("High protein") }
        preferences.append("Vary cuisines and main ingredients across the week")
        let choices = try await AIService.plan(.init(slots: requests, candidates: candidates, preferences: preferences, rules: .current()))

        var picks: [PlanPick] = []
        var taken = Set<PlanSlot>()
        for choice in choices {
            guard let day = formatter.date(from: choice.date), let mealSlot = MealSlot(rawValue: choice.slot) else { continue }
            let slot = PlanSlot(day: Kitchen.calendar.startOfDay(for: day), slot: mealSlot)
            guard let allowed = shortlist[slot], allowed.contains(choice.recipeId), !taken.contains(slot) else { continue }
            taken.insert(slot)
            picks.append(PlanPick(slot: slot, recipeID: choice.recipeId, leftoverOf: nil, reason: choice.reason ?? "Chosen for variety"))
        }
        return picks
    }

    private func shuffle(_ proposal: Proposal) {
        guard var current = proposals, let index = current.firstIndex(where: { $0.id == proposal.id }) else { return }
        var context = baseContext
        context.slot = proposal.pick.slot.slot
        context.exclude = Set(current.map(\.recipe.key))
        let pool = pool
        guard let next = Recommender.rank(pool.map(\.facts), context).first,
              let recipe = pool.first(where: { $0.key == next.id }) else {
            DropsManager.showInfo(title: "No other options fit", subtitle: "Save more recipes to widen the choice")
            return
        }
        Haptics.select()
        current[index] = Proposal(pick: PlanPick(slot: proposal.pick.slot, recipeID: next.id, leftoverOf: nil,
                                                 reason: next.reasons.joined(separator: " · ")),
                                  recipe: recipe, byAI: false)
        // Leftovers follow their dinner.
        for (i, item) in current.enumerated() where item.pick.leftoverOf == proposal.pick.slot {
            current[i] = Proposal(pick: PlanPick(slot: item.pick.slot, recipeID: next.id, leftoverOf: proposal.pick.slot,
                                                 reason: "Leftovers of \(recipe.displayTitle)"),
                                  recipe: recipe, byAI: false)
        }
        withAnimation(Theme.spring) { proposals = current }
    }

    private func accept(_ items: [Proposal]) {
        var created: [PlanSlot: PlannedMeal] = [:]
        let existing = Kitchen.meals(from: weekStart)
        var count = 0
        for item in items.sorted(by: { $0.pick.slot < $1.pick.slot }) where !skipped.contains(item.id) {
            let eaters = People.defaultEaters(for: item.pick.slot.slot)
            var source: PlannedMeal?
            if let from = item.pick.leftoverOf {
                guard !skipped.contains(from) else { continue }
                source = created[from] ?? existing.first {
                    $0.mealSlot == from.slot && Kitchen.calendar.isDate($0.day ?? .distantPast, inSameDayAs: from.day)
                }
            }
            let meal = Kitchen.plan(item.recipe, day: item.pick.slot.day, slot: item.pick.slot.slot,
                                    servings: People.servings(for: eaters), eaters: eaters,
                                    byAI: item.byAI, reason: item.pick.reason, leftoverOf: source)
            created[item.id] = meal
            count += 1
        }
        Haptics.success()
        DropsManager.showSuccess(title: "Added \(count) meals", subtitle: "Your grocery list is updated")
        dismiss()
    }
}
