import CoreData
import SwiftUI
internal import Combine

/// Search text shared between the Home header and the Cookbook tab.
@MainActor
final class CookbookSearch: ObservableObject {
    static let shared = CookbookSearch()
    @Published var query = "" {
        didSet { Personalizer.shared.searched(query) } // what they look for teaches their taste
    }
}

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var sheet: RootSheet?
    @Binding var showCookNow: Bool

    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var search = CookbookSearch.shared
    @ObservedObject private var local = LocalFood.shared
    @ObservedObject private var personal = Personalizer.shared
    @FetchRequest(sortDescriptors: [SortDescriptor(\.day)]) private var allMeals: FetchedResults<PlannedMeal>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.expiresAt)]) private var pantry: FetchedResults<PantryItem>
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isSaved == YES AND isArchived == NO AND needsReview == YES"))
    private var needsReview: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isSaved == YES")) private var saved: FetchedResults<Recipe>

    @State private var filter: MealSlot?
    @State private var searchText = ""
    @State private var cookNowMinutes: Int?
    /// New every time the app comes back to the front: a fresh mix of slides, rows and picks.
    @State private var seed = Int.random(in: 1...1_000_000)
    @Environment(\.scenePhase) private var scenePhase

    private var weekMeals: [PlannedMeal] {
        let start = Kitchen.weekStart()
        let end = Kitchen.calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return allMeals.filter { ($0.day ?? .distantPast) >= start && ($0.day ?? .distantPast) < end }
    }

    private var plannedDays: Int {
        Set(weekMeals.compactMap { $0.day.map { Kitchen.calendar.startOfDay(for: $0) } }).count
    }

    private var tonight: PlannedMeal? {
        weekMeals.first { $0.day.map { Calendar.current.isDateInToday($0) } == true && $0.mealSlot == .dinner && $0.mealStatus == .planned }
    }

    private var useSoon: [PantryItem] {
        pantry.filter { ($0.daysLeft ?? 99) <= 2 }.prefix(8).map { $0 }
    }


    var body: some View { content }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    topBar(HomeMoment(hour: Calendar.current.component(.hour, from: context.date)))
                }
                searchBar
                HomeCarousel(slides: slides).id(seed)
                weeklyPlanCard
                quickActions
                cookNowCard
                if !needsReview.isEmpty { reviewBanner }
                MoodBar()
                // The rest follows the moment and this cook's habits (see HomeLayout).
                ForEach(layout.filter { $0 != .quickActions && $0 != .cookNow && $0 != .plan }, id: \.self) { section($0) }
                HomeFeed(seed: seed)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .dockSpacing()
        .canvasBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await local.refreshIfNeeded() }
        .onChange(of: scenePhase) { old, new in
            if old == .background && new == .active { seed = Int.random(in: 1...1_000_000) }
        }
    }

    // MARK: Top — a slim greeting, search, then the strip of dishes for today

    private func topBar(_ moment: HomeMoment) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedStringKey(moment.greeting)).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                Text("\(settings.displayName) 👋").font(Theme.heading(24, .bold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            NavigationLink(value: Route.profile) {
                ProfileAvatar(size: 44)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.tick() })
            .accessibilityLabel("Open profile")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("", text: $searchText, prompt: Text("Search any dish — e.g. Aloo Puri").foregroundColor(Theme.muted))
                .foregroundStyle(Theme.ink)
                .submitLabel(.search)
                .onSubmit(runSearch)
            Button {
                Haptics.tick()
                runSearch()
            } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted)
            }
            .accessibilityLabel("Search and filter")
        }
        .font(.system(size: 14))
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
    }

    /// Today's meals, dishes they keep cooking, the best pick now, something new, local and world food.
    private var slides: [HomeSlide] {
        var slides: [HomeSlide] = []
        var used = Set<String>()
        var rng = SeededRandom(seed: UInt64(seed))
        func add(_ recipe: Recipe, _ kicker: LocalizedStringKey, _ subtitle: String?) {
            guard used.insert(recipe.key).inserted else { return }
            slides.append(HomeSlide(id: "\(slides.count)-\(recipe.key)", kicker: kicker, title: recipe.displayTitle, subtitle: subtitle,
                                    art: .recipe(recipe), route: recipe.route))
        }
        let today = Calendar.current.startOfDay(for: .now)
        for meal in weekMeals where Calendar.current.isDate(meal.day ?? .distantPast, inSameDayAs: today) {
            if let recipe = meal.recipe { add(recipe, "Today's plan", meal.mealSlot.label) }
        }
        let again = saved.filter { $0.cookedCount > 0 || $0.isFavorite }.sorted { ($0.cookedCount, $0.rating) > ($1.cookedCount, $1.rating) }.prefix(6)
        for recipe in again.shuffled(using: &rng).prefix(2) {
            add(recipe, "Cook it again", recipe.cookedCount > 0 ? "\(recipe.cookedCount)× ★\(recipe.rating > 0 ? " \(recipe.rating)" : "")" : nil)
        }
        let picks = rightNow.prefix(3)
        if let pick = picks.randomElement(using: &rng), let recipe = Kitchen.recipe(forKey: pick.id) { add(recipe, "Right now", pick.reasons.first) }
        let day = seed
        for recipe in local.untried(profile: People.profile(), seed: day, count: 2) { add(recipe, "New to you", recipe.cuisine) }
        if let recipe = local.dishes.filter({ !used.contains($0.key) }).prefix(8).randomElement(using: &rng) { add(recipe, "Popular near you", local.placeName) }
        let kitchens = WorldKitchens.featured.filter { $0.country != local.country }
        if !kitchens.isEmpty {
            let pick = kitchens[day % kitchens.count]
            slides.append(HomeSlide(id: "world-\(pick.country)", kicker: "World kitchen", title: "\(LocalFood.flag(for: pick.country)) \(LocalFood.name(for: pick.country))",
                                    subtitle: pick.dish, art: .dish(pick.dish), route: .country(pick.country)))
        }
        // Today's plan leads; everything else comes in a new order each visit.
        let planned = slides.prefix { $0.kicker == "Today's plan" }.count
        return Array(slides.prefix(planned)) + slides.dropFirst(planned).shuffled(using: &rng)
    }

    private func runSearch() {
        search.query = searchText
        Haptics.select()
        tab = .cookbook
    }

    // MARK: Cards

    private var reviewBanner: some View {
        NavigationLink(value: Route.smartCollection(.needsReview)) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.check)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(needsReview.count) recipes need a quick check")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.check)
                    Text("Amounts or allergens we weren't sure about.").font(Theme.micro).foregroundStyle(Color(hex: "#5C3A00"))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.check)
            }
            .padding(14)
            .background(Theme.checkSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var weeklyPlanCard: some View {
        Button {
            Haptics.primary()
            tab = .plan
        } label: {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Image("WeeklyPlanCard")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: 126)
                        .clipped()
                        .scaleEffect(1.15)
                        .accessibilityHidden(true)
                    LinearGradient(colors: [Color(hex: "#F53F86").opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Weekly Plan").font(.system(size: 17, weight: .bold))
                        Text("\(plannedDays)/7 days planned").font(.system(size: 13)).contentTransition(.numericText())
                        Text(plannedDays == 0 ? "Plan my week" : "View Plan")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.plan)
                            .padding(.horizontal, 21)
                            .padding(.vertical, 8)
                            .background(.white, in: Capsule())
                            .padding(.top, 5)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 17)
                }
                .frame(width: geometry.size.width, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .frame(height: 126)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel("Your weekly plan, \(plannedDays) of 7 days planned")
    }

    private func tonightCard(_ meal: PlannedMeal) -> some View {
        HStack(spacing: 14) {
            RecipeImage(recipe: meal.recipe, cornerRadius: 14).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("TONIGHT").font(Theme.label).tracking(0.8).foregroundStyle(Theme.plan)
                Text(meal.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(durationText(meal.recipe?.minutes ?? 0)) · cook \(meal.cookServings)")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let recipe = meal.recipe {
                NavigationLink(value: recipe.route) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.flameGradient, in: Circle())
                }
                .accessibilityLabel("Open \(meal.title)")
            }
        }
        .card(padding: 12)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Actions").font(Theme.section).foregroundStyle(Theme.ink)
            HStack(alignment: .top, spacing: 8) {
                quickAction("Import Recipe", symbol: "square.and.arrow.down.fill", color: Color(hex: "#FF8D35")) { sheet = .importLink }
                quickAction("Scan Recipe", symbol: "doc.text.viewfinder", color: Color(hex: "#24ADB5")) { sheet = .importScan }
                NavigationLink(value: Route.plannerSetup) {
                    quickActionLabel("Create Plan", symbol: "calendar.badge.plus", color: Color(hex: "#E45AC6"))
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .simultaneousGesture(TapGesture().onEnded { Haptics.primary() })
                quickAction("Grocery List", symbol: "basket.fill", color: Color(hex: "#9C56E9")) { tab = .shop }
            }
        }
    }

    private func quickAction(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.primary()
            action()
        } label: {
            quickActionLabel(title, symbol: symbol, color: color)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
    }

    private func quickActionLabel(_ title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 54, height: 54)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Asks the first Cook Now question right on Home.
    private var cookNowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.flameGradient, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not sure what to cook?").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("How much time do you have?").font(Theme.micro).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button {
                        Haptics.primary()
                        CookNowModel.shared.minutes = minutes
                        showCookNow = true
                    } label: {
                        Text(minutes == 60 ? "1 hr +" : "\(minutes) min")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#A8341C"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color(hex: "#FDE9E1"), in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                }
            }
        }
        .card()
    }

    private var useSoonStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Use soon", subtitle: "Before it goes to waste", actionTitle: "What can I cook?") {
                ShopIntent.openCookFromPantry = true
                tab = .shop
                NotificationCenter.default.post(name: .openCookFromPantry, object: nil)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(useSoon) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            IngredientIcon(name: item.name ?? "", size: 40)
                            Text(item.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Badge(text: item.expiryText ?? "", tone: (item.daysLeft ?? 9) <= 0 ? .red : .amber)
                        }
                        .frame(width: 112, alignment: .leading)
                        .card(padding: 12)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Adaptive layout

    private var layout: [HomeSection] {
        let moment = Moment(.now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        let habits = personal.habits
        return HomeLayout.order(at: moment, hasTonight: tonight != nil,
                                expiringToday: useSoon.contains { ($0.expiresAt ?? .distantFuture) < tomorrow },
                                cooksAtThisMoment: habits.cooksAt.isEmpty || habits.busiestMoments.prefix(3).contains(moment))
    }

    @ViewBuilder
    private func section(_ section: HomeSection) -> some View {
        switch section {
        case .rightNow: RightNowCard(picks: rightNow)
        case .tonight: if let tonight { tonightCard(tonight) }
        case .plan: weeklyPlanCard
        case .useSoon: if !useSoon.isEmpty { useSoonStrip }
        case .forYou: forYou
        case .cookNow: cookNowCard
        case .quickActions: quickActions
        case .tryNew: TryNewCard()
        case .local: LocalDishesSection()
        case .world: WorldKitchensRow()
        }
    }

    /// The best dishes for this very moment: this meal, the mood, habits and what's in the pantry.
    private var rightNow: [Ranked] {
        _ = saved.count + local.dishes.count + (personal.mood?.hashValue ?? 0)
        var context = RankContext()
        context.profile = People.profile()
        context.slot = .at(hour: Calendar.current.component(.hour, from: .now))
        context.pantry = Kitchen.pantrySignals()
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        return Array(Recommender.rank(Kitchen.candidates().map(\.facts), context).prefix(6))
    }

    // MARK: For You — ranked by the rules engine

    private var forYou: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For You").font(Theme.section).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                filterChip("All", nil)
                filterChip("Breakfast", .breakfast)
                filterChip("Lunch", .lunch)
                filterChip("Dinner", .dinner)
            }
            let picks = recommendations
            if picks.isEmpty {
                EmptyStateView(title: "Nothing fits right now",
                               message: "Your rules filter out every idea for this meal. Import a recipe or relax a filter.",
                               actionTitle: "Import a recipe") { sheet = .importLink }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(picks) { pick in
                            if let recipe = Kitchen.recipe(forKey: pick.id) {
                                NavigationLink(value: recipe.route) { forYouCard(recipe, reasons: pick.reasons) }
                                    .buttonStyle(PressableStyle(scale: 0.97))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func filterChip(_ title: String, _ slot: MealSlot?) -> some View {
        Button {
            Haptics.select()
            withAnimation(Theme.snappy) { filter = slot }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filter == slot ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(filter == slot ? Theme.ink : Theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == slot ? .isSelected : [])
    }

    private var recommendations: [Ranked] {
        _ = saved.count + (personal.mood?.hashValue ?? 0) + personal.habits.eventCount // re-rank on cookbook, mood and learning changes
        var context = RankContext()
        context.profile = People.profile()
        context.slot = filter
        context.pantry = Kitchen.pantrySignals()
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        _ = local.dishes.count // re-rank when local dishes arrive
        if let limit = settings.customizationPreferences.choices["maxTime"]?.first.flatMap({ Int($0.prefix { $0.isNumber }) }) {
            context.maxMinutes = limit
        }
        return Array(Recommender.rank(Kitchen.candidates().map(\.facts), context).prefix(8))
    }

    private func forYouCard(_ recipe: Recipe, reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            RecipeImage(recipe: recipe, cornerRadius: 0).frame(width: 230, height: 125)
            Text(recipe.displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
            HStack(spacing: 6) {
                Label(durationText(recipe.minutes), systemImage: "clock").font(.system(size: 11)).foregroundStyle(Theme.muted)
                if let reason = reasons.first(where: { !$0.hasPrefix("Ready in") }) {
                    Text(reason).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.pantry).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: 230, alignment: .leading)
        .padding(.bottom, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

/// Repeatable shuffles for one Home visit (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Notification.Name {
    static let openCookFromPantry = Notification.Name("flavourly.openCookFromPantry")
}
