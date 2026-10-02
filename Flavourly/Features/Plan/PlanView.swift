import CoreData
import SwiftUI

struct PlanTarget: Identifiable, Hashable {
    let day: Date
    let slot: MealSlot
    var id: String { "\(day.timeIntervalSince1970)-\(slot.rawValue)" }
}

/// The week: every meal with who's eating, locks, leftovers and cooked state.
struct PlanView: View {
    @EnvironmentObject private var settings: SettingsManager
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "day", ascending: true), NSSortDescriptor(key: "sortIndex", ascending: true)],
                  predicate: PlanView.predicate(for: Kitchen.weekStart()))
    private var meals: FetchedResults<PlannedMeal>

    @State private var weekStart = Kitchen.weekStart()
    @State private var actionsFor: PlannedMeal?
    @State private var addTarget: PlanTarget?
    @State private var cooking: PlannedMeal?

    static func predicate(for start: Date) -> NSPredicate {
        let end = Kitchen.calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return NSPredicate(format: "day >= %@ AND day < %@", start as NSDate, end as NSDate)
    }

    private var days: [Date] { Kitchen.days(from: weekStart) }
    private var isThisWeek: Bool { Kitchen.calendar.isDate(weekStart, inSameDayAs: Kitchen.weekStart()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                weekSwitcher
                summary
                ForEach(days, id: \.self) { day in
                    DaySection(day: day, meals: meals.filter { Kitchen.calendar.isDate($0.day ?? .distantPast, inSameDayAs: day) },
                               onActions: { actionsFor = $0 }, onAdd: { addTarget = PlanTarget(day: day, slot: $0) })
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .dockSpacing()
        .canvasBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: weekStart) { _, start in
            withAnimation(Theme.spring) { meals.nsPredicate = Self.predicate(for: start) }
        }
        .sheet(item: $actionsFor) { meal in
            MealActionsSheet(meal: meal) { cook in
                actionsFor = nil
                if cook { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { cooking = meal } }
            }
            .environmentObject(settings)
        }
        .sheet(item: $addTarget) { target in AddMealSheet(target: target).environmentObject(settings) }
        .fullScreenCover(item: $cooking) { meal in
            if let recipe = meal.recipe {
                CookFlowView(recipe: recipe, servings: meal.cookServings, meal: meal).environmentObject(settings)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meal plan").font(Theme.pageTitle).foregroundStyle(Theme.ink)
                Text("Locked meals are never changed by the planner").font(Theme.micro).foregroundStyle(Theme.muted)
            }
            Spacer()
            NavigationLink(value: Route.plannerSetup) {
                Label("Plan my week", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Theme.aiGradient, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.primary() })
        }
    }

    private var weekSwitcher: some View {
        HStack {
            IconButton(systemImage: "chevron.left", label: "Previous week", style: .bordered) { shiftWeek(-7) }
            Spacer()
            VStack(spacing: 1) {
                Text(isThisWeek ? "This week" : weekLabel).font(.system(size: 16, weight: .semibold))
                Text(rangeLabel).font(Theme.micro).foregroundStyle(Theme.muted)
            }
            .contentTransition(.opacity)
            .onTapGesture { if !isThisWeek { shiftWeek(nil) } }
            Spacer()
            IconButton(systemImage: "chevron.right", label: "Next week", style: .bordered) { shiftWeek(7) }
        }
    }

    private var summary: some View {
        let planned = meals.filter { $0.mealStatus != .skipped }
        let cooked = meals.filter { $0.mealStatus == .cooked }.count
        let dinners = Set(planned.filter { $0.mealSlot == .dinner }.compactMap { $0.day.map { Kitchen.calendar.startOfDay(for: $0) } }).count
        let state = Kitchen.groceryState(weekStart: weekStart)
        let toBuy = Kitchen.groceryLines(weekStart: weekStart, system: settings.unitSystem).filter { line in
            !line.coveredByPantry && !line.isStaple && !(state[line.key].map { $0.isChecked || $0.isHidden } ?? false)
        }.count
        return HStack(spacing: 0) {
            stat("\(dinners)/7", "dinners planned", Theme.plan)
            Divider().frame(height: 34)
            stat("\(cooked)", "cooked", Theme.green)
            Divider().frame(height: 34)
            Button {
                Haptics.select()
                NotificationCenter.default.post(name: .switchTab, object: AppTab.shop)
            } label: {
                stat("\(toBuy)", "to buy ›", Theme.pantry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(toBuy) items to buy. Open grocery list")
        }
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.rounded(22)).foregroundStyle(tint).contentTransition(.numericText())
            Text(label).font(Theme.micro).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekLabel: String {
        let weeks = (Kitchen.calendar.dateComponents([.day], from: Kitchen.weekStart(), to: weekStart).day ?? 0) / 7
        switch weeks {
        case 1: return "Next week"
        case -1: return "Last week"
        default: return weeks > 0 ? "In \(weeks) weeks" : "\(-weeks) weeks ago"
        }
    }

    private var rangeLabel: String {
        let end = Kitchen.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.day().month())) – \(end.formatted(.dateTime.day().month()))"
    }

    private func shiftWeek(_ days: Int?) {
        Haptics.select()
        weekStart = days.flatMap { Kitchen.calendar.date(byAdding: .day, value: $0, to: weekStart) } ?? Kitchen.weekStart()
    }
}

// MARK: - Day

private struct DaySection: View {
    let day: Date
    let meals: [PlannedMeal]
    let onActions: (PlannedMeal) -> Void
    let onAdd: (MealSlot) -> Void

    private var isToday: Bool { Kitchen.calendar.isDateInToday(day) }
    private var isPast: Bool { day < Kitchen.calendar.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isToday ? Theme.plan : Theme.ink)
                Text(day.formatted(.dateTime.day().month())).font(Theme.micro).foregroundStyle(Theme.muted)
                Spacer()
                if let calories = caloriesForMe, calories > 0 {
                    let target = People.me().calorieTarget
                    Text(target > 0 ? "\(calories) / \(target) kcal" : "≈ \(calories) kcal")
                        .font(Theme.micro.weight(.semibold))
                        .foregroundStyle(target > 0 && calories > target ? Theme.check : Theme.muted)
                }
            }
            ForEach(meals.sorted { $0.mealSlot < $1.mealSlot }) { meal in
                MealCard(meal: meal) { onActions(meal) }
            }
            let empty = MealSlot.allCases.filter { slot in !meals.contains { $0.mealSlot == slot } }
            if !empty.isEmpty && !isPast {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(empty) { slot in
                            Button {
                                Haptics.tick()
                                onAdd(slot)
                            } label: {
                                Label(slot.label, systemImage: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(slot == .dinner ? Theme.plan : Theme.ink2)
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .background(slot == .dinner ? Theme.planSoft : .white, in: Capsule())
                                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                        .foregroundStyle(slot == .dinner ? Theme.plan.opacity(0.5) : Theme.line))
                            }
                            .buttonStyle(PressableStyle(scale: 0.94))
                            .accessibilityLabel("Add \(slot.label.lowercased()) on \(day.formatted(.dateTime.weekday(.wide)))")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .background(isToday ? AnyShapeStyle(Theme.planSoft.opacity(0.45)) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(isPast ? 0.75 : 1)
    }

    /// What "me" eats that day, one serving per meal.
    private var caloriesForMe: Int? {
        let mine = meals.filter { $0.mealStatus != .skipped && $0.eaterIDs.contains(Person.meID) }
        guard !mine.isEmpty else { return nil }
        return Int(mine.compactMap { $0.recipe?.calories }.reduce(0, +))
    }
}

// MARK: - Meal card

struct MealCard: View {
    @ObservedObject var meal: PlannedMeal
    let onActions: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let recipe = meal.recipe {
                    NavigationLink(value: recipe.route) { content }.buttonStyle(.plain)
                } else {
                    Button(action: onActions) { content }.buttonStyle(.plain)
                }
            }
            Button {
                Haptics.primary()
                onActions()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 40, height: 40)
                    .background(Theme.chip, in: Circle())
            }
            .accessibilityLabel("Actions for \(meal.title)")
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(meal.isLocked ? Theme.plan.opacity(0.4) : Theme.hairline))
        .opacity(meal.mealStatus == .skipped ? 0.55 : 1)
        .contextMenu {
            Button { Kitchen.setStatus(meal, meal.mealStatus == .cooked ? .planned : .cooked); Haptics.success() } label: {
                Label(meal.mealStatus == .cooked ? "Mark as not cooked" : "Mark as cooked", systemImage: "checkmark.circle")
            }
            Button { Kitchen.toggleLock(meal); Haptics.thud() } label: {
                Label(meal.isLocked ? "Unlock" : "Lock", systemImage: meal.isLocked ? "lock.open" : "lock")
            }
            Button(role: .destructive) {
                Haptics.destructive()
                Kitchen.remove(meal)
                DropsManager.showInfo(title: "Removed from plan")
            } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let recipe = meal.recipe {
                    RecipeImage(recipe: recipe, cornerRadius: 14).frame(width: 64, height: 64)
                } else {
                    IconTile(systemImage: "fork.knife", tint: Theme.plan, size: 64)
                }
                if meal.mealStatus == .cooked {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Theme.green).offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.mealSlot.label.uppercased()).font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                Text(meal.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    .strikethrough(meal.mealStatus == .skipped)
                HStack(spacing: 5) {
                    EaterStack(ids: meal.eaterIDs)
                    if meal.isLocked { Badge(text: "Locked", systemImage: "lock.fill", tone: .pink) }
                    if meal.isLeftover { Badge(text: "Leftovers", systemImage: "arrow.uturn.backward", tone: .teal) }
                    else if meal.extraServings > 0 { Badge(text: "+\(meal.extraServings) extra", tone: .teal) }
                    if meal.createdByAI { Badge(text: "AI", systemImage: "sparkles", tone: .purple) }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Up to three overlapping avatars for the people eating a meal.
struct EaterStack: View {
    let ids: [String]

    var body: some View {
        let people = People.all().filter { ids.contains($0.id) }
        HStack(spacing: -7) {
            ForEach(people.prefix(3)) { person in
                Avatar(initial: person.initial, color: person.color, size: 20, ringed: true)
            }
            if people.count > 3 {
                Text("+\(people.count - 3)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ink2).padding(.leading, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people.map { $0.isMe ? "You" : $0.name }.joined(separator: ", "))
    }
}

// MARK: - Meal actions

struct MealActionsSheet: View {
    @ObservedObject var meal: PlannedMeal
    /// true = start cooking after the sheet closes.
    let onClose: (Bool) -> Void

    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(title: meal.title,
                                subtitle: "\(meal.mealSlot.label) · \((meal.day ?? .now).formatted(.dateTime.weekday(.wide).day().month()))") {
                        onClose(false)
                    }
                    if let reason = meal.aiReason, !reason.isEmpty {
                        Label(reason, systemImage: "sparkles").font(Theme.caption).foregroundStyle(Theme.aiDeep)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.aiSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if let source = meal.leftoverSource {
                        Label("Leftovers of \(source.title) (\((source.day ?? .now).formatted(.dateTime.weekday(.wide))))", systemImage: "arrow.uturn.backward")
                            .font(Theme.caption).foregroundStyle(Theme.pantry)
                    } else if meal.extraServings > 0 {
                        Label("Cooks \(meal.extraServings) extra servings for leftovers", systemImage: "takeoutbag.and.cup.and.straw")
                            .font(Theme.caption).foregroundStyle(Theme.pantry)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        if meal.recipe != nil && meal.mealStatus != .cooked {
                            action("Cook now", "flame.fill", Theme.capture) { onClose(true) }
                        }
                        action(meal.mealStatus == .cooked ? "Not cooked" : "Mark cooked", "checkmark.circle.fill", Theme.green) {
                            Kitchen.setStatus(meal, meal.mealStatus == .cooked ? .planned : .cooked)
                            Haptics.success()
                            DropsManager.showSuccess(title: meal.mealStatus == .cooked ? "Marked as cooked" : "Marked as planned")
                        }
                        action(meal.mealStatus == .skipped ? "Un-skip" : "Skip", "forward.fill", Theme.ink2) {
                            Kitchen.setStatus(meal, meal.mealStatus == .skipped ? .planned : .skipped)
                            Haptics.tick()
                            DropsManager.showInfo(title: meal.mealStatus == .skipped ? "Skipped — removed from your list" : "Back on the plan")
                        }
                        action(meal.isLocked ? "Unlock" : "Lock", meal.isLocked ? "lock.open.fill" : "lock.fill", Theme.plan) {
                            Kitchen.toggleLock(meal)
                            Haptics.thud()
                            DropsManager.showInfo(title: meal.isLocked ? "Locked" : "Unlocked",
                                                  subtitle: meal.isLocked ? "The planner will never change this meal" : nil)
                        }
                    }

                    VStack(spacing: 0) {
                        NavigationLink {
                            SwapMealView(meal: meal) { onClose(false) }
                        } label: {
                            row("Swap for something else", "arrow.left.arrow.right", locked: meal.isLocked)
                        }
                        .disabled(meal.isLocked)
                        Divider().padding(.leading, 46)
                        NavigationLink {
                            MoveMealView(meal: meal, duplicate: false) { onClose(false) }
                        } label: { row("Move to another day", "calendar", locked: meal.isLocked) }
                        .disabled(meal.isLocked)
                        Divider().padding(.leading, 46)
                        NavigationLink {
                            MoveMealView(meal: meal, duplicate: true) { onClose(false) }
                        } label: { row("Repeat on another day", "plus.square.on.square", locked: false) }
                    }
                    .buttonStyle(.plain)
                    .card(padding: 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHO'S EATING").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(People.all()) { person in
                                let isOn = meal.eaterIDs.contains(person.id)
                                Chip(title: person.isMe ? "You" : person.name, isOn: isOn, style: .green, small: true) {
                                    var ids = meal.eaterIDs
                                    if isOn { ids.removeAll { $0 == person.id } } else { ids.append(person.id) }
                                    guard !ids.isEmpty else { return }
                                    Kitchen.setEaters(meal, ids)
                                }
                            }
                        }
                        HStack {
                            Text("Servings").font(.system(size: 15, weight: .medium))
                            Spacer()
                            StepperPill(value: Binding(get: { Int(meal.servings) }, set: { Kitchen.setServings(meal, $0) }), range: 1...40)
                        }
                        let check = FoodRules.check(ingredients: meal.recipe?.checkLines ?? [], profile: People.profile(for: meal.eaterIDs))
                        if check.isBlocked, let issue = check.issues.first(where: { $0.severity == .blocked }) {
                            Label(issue.reason, systemImage: "exclamationmark.shield.fill").font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.allergen)
                        }
                    }
                    .card(padding: 14)

                    Button(role: .destructive) { confirmRemove = true } label: {
                        Label("Remove from plan", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .tint(Theme.allergen)
                }
                .padding(20)
            }
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Remove \(meal.title)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Haptics.destructive()
                    Kitchen.remove(meal)
                    DropsManager.showInfo(title: "Removed from plan")
                    onClose(false)
                }
            } message: {
                Text(meal.leftoverChildren.isEmpty ? "Its ingredients leave your grocery list." : "Its planned leftovers are removed too.")
            }
        }
        .presentationDetents([.large])
    }

    private func action(_ title: String, _ symbol: String, _ tint: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    private func row(_ title: String, _ symbol: String, locked: Bool) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: symbol, tint: Theme.ink2, size: 32)
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(locked ? Theme.muted : Theme.ink)
            Spacer()
            Image(systemName: locked ? "lock.fill" : "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}

/// Alternatives for a meal, ranked for the same slot and the same eaters.
struct SwapMealView: View {
    @ObservedObject var meal: PlannedMeal
    let onDone: () -> Void
    @EnvironmentObject private var settings: SettingsManager

    private var options: [(Recipe, Ranked)] {
        var context = RankContext()
        context.profile = People.profile(for: meal.eaterIDs)
        context.slot = meal.mealSlot
        context.pantry = Kitchen.pantrySignals()
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        if let current = meal.recipe { context.exclude = [current.key] }
        let pool = Kitchen.candidates()
        let byKey = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return Recommender.rank(pool.map(\.facts), context).prefix(10).compactMap { rank in byKey[rank.id].map { ($0, rank) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Safe for everyone eating, and suits \(meal.mealSlot.label.lowercased()).")
                    .font(Theme.caption).foregroundStyle(Theme.muted)
                ForEach(options, id: \.1.id) { recipe, rank in
                    Button {
                        Kitchen.replace(meal, with: recipe)
                        Haptics.success()
                        DropsManager.showSuccess(title: "Swapped", subtitle: recipe.displayTitle)
                        onDone()
                    } label: {
                        HStack(spacing: 12) {
                            RecipeImage(recipe: recipe, cornerRadius: 12).frame(width: 60, height: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.displayTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                                Text(rank.reasons.joined(separator: " · ")).font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.green)
                        }
                        .card(padding: 10)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
                if options.isEmpty {
                    EmptyStateView(systemImage: "arrow.left.arrow.right", title: "No other options",
                                   message: "Nothing else fits everyone's rules for this meal. Save more recipes to widen the choice.")
                }
            }
            .padding(20)
        }
        .canvasBackground()
        .navigationTitle("Swap \(meal.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Move a meal (or repeat it) to another day and slot.
struct MoveMealView: View {
    @ObservedObject var meal: PlannedMeal
    let duplicate: Bool
    let onDone: () -> Void

    @State private var day = Kitchen.calendar.startOfDay(for: .now)
    @State private var slot: MealSlot = .dinner

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Kitchen.days(from: .now, count: 14), id: \.self) { date in
                        let isOn = Kitchen.calendar.isDate(date, inSameDayAs: day)
                        Button {
                            Haptics.select()
                            day = date
                        } label: {
                            VStack(spacing: 3) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, weight: .semibold))
                                Text(date.formatted(.dateTime.day())).font(.system(size: 18, weight: .bold))
                            }
                            .foregroundStyle(isOn ? .white : Theme.ink)
                            .frame(width: 52, height: 60)
                            .background(isOn ? AnyShapeStyle(Theme.greenGradient) : AnyShapeStyle(Color.white),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isOn ? .clear : Theme.line))
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                }
            }
            .scrollIndicators(.hidden)
            Picker("Meal", selection: $slot) {
                ForEach(MealSlot.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
            }
            .pickerStyle(.segmented)
            Spacer()
            PrimaryButton(title: duplicate ? "Repeat on \(day.formatted(.dateTime.weekday(.wide)))" : "Move to \(day.formatted(.dateTime.weekday(.wide)))",
                          systemImage: duplicate ? "plus.square.on.square" : "arrow.right") {
                if duplicate {
                    Kitchen.duplicate(meal, to: day, slot: slot)
                    DropsManager.showSuccess(title: "Added to \(day.formatted(.dateTime.weekday(.wide)))")
                } else {
                    Kitchen.move(meal, to: day, slot: slot)
                    Haptics.thud()
                    DropsManager.showSuccess(title: "Moved to \(day.formatted(.dateTime.weekday(.wide)))")
                }
                onDone()
            }
        }
        .padding(20)
        .canvasBackground()
        .navigationTitle(duplicate ? "Repeat meal" : "Move meal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            day = meal.day.map { Kitchen.calendar.startOfDay(for: $0) } ?? day
            slot = meal.mealSlot
        }
    }
}

// MARK: - Add a meal to an empty slot

struct AddMealSheet: View {
    let target: PlanTarget

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)],
                  predicate: NSPredicate(format: "isSaved == YES AND isArchived == NO"))
    private var recipes: FetchedResults<Recipe>
    @State private var query = ""
    @State private var custom = ""

    private var eaters: [String] { People.defaultEaters(for: target.slot) }

    private var suggestions: [(Recipe, Ranked)] {
        var context = RankContext()
        context.profile = People.profile(for: eaters)
        context.slot = target.slot
        context.pantry = Kitchen.pantrySignals()
        context.craving = query
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        context.exclude = Set(Kitchen.meals(from: target.day, days: 1).compactMap { $0.recipe?.key })
        let pool = Kitchen.candidates()
        let byKey = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return Recommender.rank(pool.map(\.facts), context).prefix(8).compactMap { rank in byKey[rank.id].map { ($0, rank) } }
    }

    private var matches: [Recipe] {
        let key = FoodText.normalize(query)
        guard !key.isEmpty else { return [] }
        return recipes.filter { FoodText.normalize($0.displayTitle).contains(key) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SheetHeader(title: "Add \(target.slot.label.lowercased())",
                                subtitle: target.day.formatted(.dateTime.weekday(.wide).day().month())) { dismiss() }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("Search or type a craving", text: $query)
                    }
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))

                    if !matches.isEmpty {
                        Text("YOUR RECIPES").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                        ForEach(matches.prefix(6)) { recipe in pickRow(recipe, reason: nil, check: nil) }
                    }
                    Text(query.isEmpty ? "SUGGESTED FOR THIS MEAL" : "BEST MATCHES").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                    ForEach(suggestions, id: \.1.id) { recipe, rank in
                        pickRow(recipe, reason: rank.reasons.first, check: rank.check)
                    }
                    if suggestions.isEmpty {
                        Text("Nothing in your cookbook fits this meal and everyone's rules yet.").font(Theme.caption).foregroundStyle(Theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SOMETHING ELSE").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(["Eating out", "Takeaway", "Freezer meal", "Leftovers", "Sandwiches"], id: \.self) { option in
                                Chip(title: option, isOn: custom == option, style: .outline, small: true) { custom = option }
                            }
                        }
                        HStack {
                            TextField("Or type anything", text: $custom)
                                .padding(12)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button("Add") { addCustom() }
                                .font(.system(size: 15, weight: .semibold))
                                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                                .tint(Theme.green)
                        }
                        if !custom.isEmpty { FieldError(message: Validate.required(custom, field: "Meal name", max: Validate.Limit.customMeal).message) }
                    }
                    .card(padding: 14)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvasBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func pickRow(_ recipe: Recipe, reason: String?, check: FoodCheckResult?) -> some View {
        Button {
            Kitchen.plan(recipe, day: target.day, slot: target.slot, servings: People.servings(for: eaters), eaters: eaters)
            Haptics.success()
            DropsManager.showSuccess(title: "Added to \(target.day.formatted(.dateTime.weekday(.wide)))", subtitle: recipe.displayTitle)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RecipeImage(recipe: recipe, cornerRadius: 12).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.displayTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    if let reason { Text(reason).font(Theme.micro).foregroundStyle(Theme.green).lineLimit(1) }
                    if check?.needsCheck == true { Text("Please check allergens").font(Theme.micro).foregroundStyle(Theme.check) }
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.green)
            }
            .card(padding: 10)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func addCustom() {
        let check = Validate.required(custom, field: "Meal name", max: Validate.Limit.customMeal)
        guard check.isValid else {
            Haptics.error()
            return
        }
        let title = check.value
        Kitchen.plan(nil, customTitle: title, day: target.day, slot: target.slot, servings: People.servings(for: eaters), eaters: eaters)
        Haptics.success()
        DropsManager.showSuccess(title: "Added \(title)")
        dismiss()
    }
}
