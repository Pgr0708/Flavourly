import CoreData
import SwiftUI
internal import Combine

/// Search text shared between the Home header and the Cookbook tab.
@MainActor
final class CookbookSearch: ObservableObject {
    static let shared = CookbookSearch()
    @Published var query = ""
}

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var sheet: RootSheet?
    @Binding var showCookNow: Bool

    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var search = CookbookSearch.shared
    @ObservedObject private var local = LocalFood.shared
    @FetchRequest(sortDescriptors: [SortDescriptor(\.day)]) private var allMeals: FetchedResults<PlannedMeal>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.expiresAt)]) private var pantry: FetchedResults<PantryItem>
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isSaved == YES AND isArchived == NO AND needsReview == YES"))
    private var needsReview: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isSaved == YES")) private var saved: FetchedResults<Recipe>

    @State private var filter: MealSlot?
    @State private var searchText = ""
    @State private var cookNowMinutes: Int?

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

    private let headerHeight: CGFloat = 300

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            content
                // Once the content sheet reaches the status bar, a soft bar keeps the clock and battery readable.
                .overlayPreferenceValue(HeaderOffsetKey.self, alignment: .top) { minY in
                    let gone = minY < top + 8
                    Theme.canvas.opacity(0.97)
                        .frame(height: top)
                        .offset(y: -top) // the overlay starts below the status bar; cover the status bar itself
                        .opacity(gone ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: gone)
                        .allowsHitTesting(false)
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    header(HomeMoment(hour: Calendar.current.component(.hour, from: context.date)))
                }

                // The content sheet slides over the photo with rounded corners, like a card pulled up.
                VStack(alignment: .leading, spacing: 24) {
                    if !needsReview.isEmpty { reviewBanner }
                    weeklyPlanCard
                    if let tonight { tonightCard(tonight) }
                    quickActions
                    cookNowCard
                    TryNewCard()
                    LocalDishesSection()
                    if !useSoon.isEmpty { useSoonStrip }
                    forYou
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .background(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                        .fill(Theme.canvas)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                }
                .padding(.top, -30)
                .background {
                    // Tracked here, not on the header: the sheet stays on screen, so its position keeps updating.
                    GeometryReader { Color.clear.preference(key: HeaderOffsetKey.self, value: $0.frame(in: .global).minY) }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .dockSpacing()
        .canvasBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await local.refreshIfNeeded() }
    }

    // MARK: Header — full-bleed photo under the status bar that stretches when pulled down

    private func header(_ moment: HomeMoment) -> some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .global).minY
            let pull = max(0, minY)
            ZStack(alignment: .topLeading) {
                Image(moment.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: headerHeight + pull)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.05), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .leading, endPoint: .center)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(moment.greeting).font(Theme.heading(26, .bold))
                            Text("\(settings.displayName)! 👋").font(Theme.brand(30)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        Spacer()
                        NavigationLink(value: Route.profile) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 21))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial.opacity(0.9), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.35)))
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tick() })
                        .accessibilityLabel("Open profile")
                    }
                    Spacer(minLength: 16)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("", text: $searchText, prompt: Text("Search recipes, ingredients...").foregroundColor(Theme.muted))
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
                    .background(.white.opacity(0.94), in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 64 + pull)
                .padding(.bottom, 52)
            }
            .frame(width: geometry.size.width, height: headerHeight + pull)
            .offset(y: -pull)
        }
        .frame(height: headerHeight)
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
                    Text("\(needsReview.count) recipe\(needsReview.count == 1 ? "" : "s") need a quick check")
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
        _ = saved.count // re-rank when the cookbook changes
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

private struct HeaderOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

extension Notification.Name {
    static let openCookFromPantry = Notification.Name("flavourly.openCookFromPantry")
}
