import SwiftUI

enum DiscoverCategory: String, CaseIterable, Identifiable {
    case local, breakfast, quick, protein, mealPrep, snacks, kids, onePot

    var id: String { rawValue }
    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .quick: "Quick"
        case .protein: "Protein"
        case .mealPrep: "Meal prep"
        case .snacks: "Snacks"
        case .kids: "Kid-friendly"
        case .onePot: "One-pot"
        case .local: LocalFood.shared.cuisine
        }
    }
    var symbol: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .quick: "bolt.fill"
        case .protein: "dumbbell.fill"
        case .mealPrep: "shippingbox.fill"
        case .snacks: "leaf.fill"
        case .kids: "figure.and.child.holdinghands"
        case .onePot: "frying.pan.fill"
        case .local: "house.fill"
        }
    }
    var tint: Color {
        switch self {
        case .breakfast: Theme.capture
        case .quick: Theme.green
        case .protein: Theme.plan
        case .mealPrep: Theme.pantry
        case .snacks: Theme.aiDeep
        case .kids: Color(hex: "#8A5A00")
        case .onePot: Theme.allergen
        case .local: Theme.ink2
        }
    }

    func matches(_ recipe: Recipe) -> Bool {
        let tags = recipe.tagList.map { $0.lowercased() }
        switch self {
        case .breakfast: return recipe.slots.contains(.breakfast)
        case .quick: return recipe.minutes > 0 && recipe.minutes <= 20
        case .protein: return recipe.protein >= 25 || tags.contains("high protein")
        case .mealPrep: return tags.contains("meal prep")
        case .snacks: return recipe.slots.contains(.snack)
        case .kids: return tags.contains("kid-friendly") || !recipe.checkLines.contains(where: FoodRules.isSpicy)
        case .onePot: return tags.contains("one-pan") || tags.contains("one-pot")
        case .local: return recipe.cuisine?.caseInsensitiveCompare(LocalFood.shared.cuisine) == .orderedSame
        }
    }
}

/// Discover lives inside the Cookbook tab and is also pushable on its own.
struct DiscoverView: View {
    var body: some View {
        ScrollView { DiscoverContent() }
            .dockSpacing()
            .canvasBackground()
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct DiscoverContent: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var local = LocalFood.shared
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isSaved == YES")) private var saved: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: []) private var pantry: FetchedResults<PantryItem>
    @State private var category: DiscoverCategory?

    private var ranked: [(Recipe, Ranked)] {
        _ = saved.count + pantry.count + local.dishes.count
        var context = RankContext()
        context.profile = People.profile()
        context.pantry = Kitchen.pantrySignals()
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        let pool = Kitchen.candidates().filter { category?.matches($0) ?? true }
        let byKey = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return Recommender.rank(pool.map(\.facts), context).compactMap { rank in byKey[rank.id].map { ($0, rank) } }
    }

    var body: some View {
        let all = ranked
        VStack(alignment: .leading, spacing: 18) {
            rulesRow
            heroCard
            if category == nil {
                LocalDishesSection()
                WorldKitchensRow()
            }
            browseGrid
            if category == nil {
                let pantryPicks = all.filter { !$0.1.have.isEmpty }.sorted { $0.1.coverage > $1.1.coverage }.prefix(3)
                if !pantryPicks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Uses what you have", actionTitle: "See all") {}
                        ForEach(Array(pantryPicks), id: \.1.id) { recipe, rank in DiscoverRow(recipe: recipe, rank: rank, showPantry: true) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: category.map { "\($0.title) ideas" } ?? "Picked for you",
                              subtitle: "\(all.count) fit your rules")
                if all.isEmpty {
                    EmptyStateView(systemImage: "line.3.horizontal.decrease.circle", title: "No ideas fit",
                                   message: "Your allergies, diet and dislikes rule out everything in this category.")
                } else {
                    ForEach(all, id: \.1.id) { recipe, rank in DiscoverRow(recipe: recipe, rank: rank) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var rulesRow: some View {
        let profile = People.profile()
        let limit = settings.customizationPreferences.choices["maxTime"]?.first
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if !profile.allergens.isEmpty || !profile.customAllergens.isEmpty {
                    Badge(text: "No \(profile.allergenSummary)", systemImage: "checkmark.shield.fill", tone: .green)
                }
                ForEach(profile.diets.keys.sorted { $0.rawValue < $1.rawValue }) { Badge(text: $0.label, tone: .neutral) }
                if let limit, limit != "No limit" { Badge(text: "≤ \(limit)", tone: .neutral) }
                ForEach(profile.dislikes.keys.sorted().prefix(3), id: \.self) { Badge(text: "No \($0)", tone: .neutral) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var heroCard: some View {
        Button {
            Haptics.primary()
            withAnimation(Theme.spring) { category = category == .quick ? nil : .quick }
        } label: {
            ZStack(alignment: .leading) {
                Image("RecipeChickenBowl").resizable().scaledToFill().frame(height: 150).clipped()
                LinearGradient(colors: [Color(hex: "#12281A").opacity(0.88), Color(hex: "#12281A").opacity(0.5), .clear],
                               startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PICKED FOR THIS WEEK").font(Theme.label).tracking(0.8).foregroundStyle(Color(hex: "#CDEBC0"))
                    Text("20-minute\ndinners").font(Theme.display(27)).foregroundStyle(.white)
                    Text(category == .quick ? "Showing quick ideas · tap to clear" : "Tap to see what fits your rules")
                        .font(Theme.micro).foregroundStyle(.white.opacity(0.88))
                }
                .padding(18)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var browseGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(DiscoverCategory.allCases) { item in
                    Button {
                        Haptics.select()
                        withAnimation(Theme.spring) { category = category == item ? nil : item }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(category == item ? .white : item.tint)
                                .frame(width: 54, height: 54)
                                .background(category == item ? AnyShapeStyle(item.tint) : AnyShapeStyle(item.tint.opacity(0.12)),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(item.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                        }
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
        }
    }
}

struct DiscoverRow: View {
    @ObservedObject var recipe: Recipe
    let rank: Ranked
    var showPantry = false

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: recipe.route) {
                HStack(spacing: 12) {
                    RecipeImage(recipe: recipe, cornerRadius: 14).frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.displayTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text([recipe.minutes > 0 ? "\(recipe.minutes) min" : nil, recipe.calories > 0 ? "\(Int(recipe.calories)) kcal" : nil, recipe.cuisine]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.micro).foregroundStyle(Theme.muted)
                        HStack(spacing: 4) {
                            if showPantry, !rank.have.isEmpty {
                                Badge(text: "Have \(rank.have.count) of \(rank.have.count + rank.missing.count)", tone: .teal)
                            } else if let reason = rank.reasons.first(where: { !$0.hasPrefix("Ready in") }) {
                                Badge(text: reason, tone: reason.hasPrefix("Uses") ? .teal : .green)
                            }
                            if rank.check.needsCheck { Badge(text: "Check", systemImage: "exclamationmark.triangle.fill", tone: .amber) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button {
                Haptics.success()
                let target = Kitchen.adopt(recipe)
                DropsManager.showSuccess(title: "Saved to your cookbook", subtitle: target.displayTitle)
            } label: {
                Image(systemName: recipe.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .frame(width: 44, height: 44)
            }
            .disabled(recipe.isSaved)
            .accessibilityLabel(recipe.isSaved ? "Saved" : "Save \(recipe.displayTitle)")
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}
