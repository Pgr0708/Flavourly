import SwiftUI

/// The lower half of Home: rows built from this cook's own history ("Because you cooked…", their
/// favourite cuisine, what the pantry can make) in a new order every visit, then "More for you" — an
/// endless list that pages through every dish that fits and, after that, the world's kitchens.
struct HomeFeed: View {
    /// Changes every time the app comes back, so Home never looks the same twice.
    let seed: Int

    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var personal = Personalizer.shared
    @ObservedObject private var local = LocalFood.shared

    private struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let recipes: [Recipe]
    }

    @State private var rows: [Row] = []
    @State private var feed: [Recipe] = []
    @State private var shown = 10
    @State private var nextKitchen = 0
    @State private var loadingMore = false

    private var buildKey: String {
        "\(seed)-\(local.dishes.count)-\(personal.mood?.rawValue ?? "")-\(personal.habits.eventCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(rows) { row in rowView(row) }
            if !feed.isEmpty { moreForYou }
        }
        .task(id: buildKey) { build() }
    }

    // MARK: Rows

    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(Theme.heading(19)).foregroundStyle(Theme.ink).lineLimit(1)
                if let subtitle = row.subtitle { Text(subtitle).font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(row.recipes, id: \.key) { recipe in
                        NavigationLink(value: recipe.route) { smallCard(recipe) }.buttonStyle(PressableStyle(scale: 0.97))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func smallCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipeImage(recipe: recipe, cornerRadius: 0).frame(width: 160, height: 112)
            Text(recipe.displayTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).padding(.horizontal, 9)
            if recipe.minutes > 0 {
                Label(durationText(recipe.minutes), systemImage: "clock").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 9)
            }
        }
        .frame(width: 160, alignment: .leading)
        .padding(.bottom, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: More for you — endless

    private var moreForYou: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More for you").font(Theme.section).foregroundStyle(Theme.ink)
            LazyVStack(spacing: 14) {
                ForEach(Array(feed.prefix(shown).enumerated()), id: \.element.key) { index, recipe in
                    NavigationLink(value: recipe.route) { wideCard(recipe) }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .onAppear { if index >= shown - 3 { Task { await loadMore() } } }
                }
            }
            if loadingMore { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8) }
        }
    }

    private func wideCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(recipe: recipe, cornerRadius: 0).frame(height: 180).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.displayTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    if recipe.minutes > 0 { Label(durationText(recipe.minutes), systemImage: "clock") }
                    if let cuisine = recipe.cuisine, !cuisine.isEmpty { Label(cuisine, systemImage: "globe") }
                    if recipe.isFavorite { Image(systemName: "heart.fill").foregroundStyle(Theme.plan) }
                }
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .padding(12)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    /// Shows ten more; when every fitting dish is out, brings in the next world kitchen (shared and cached
    /// on the server, so this almost never costs an AI call).
    private func loadMore() async {
        if shown < feed.count {
            shown = min(shown + 10, feed.count)
            return
        }
        guard !loadingMore else { return }
        let kitchens = WorldKitchens.featured.map(\.country).filter { $0 != local.country }
        guard nextKitchen < kitchens.count else { return }
        loadingMore = true
        defer { loadingMore = false }
        let country = kitchens[(nextKitchen + seed) % kitchens.count]
        nextKitchen += 1
        let profile = People.profile()
        let have = Set(feed.map(\.key))
        let more = ((try? await WorldKitchens.dishes(country: country, region: nil)) ?? [])
            .filter { !have.contains($0.key) && LocalFood.fits($0, profile) }
        feed += more.sorted { mix($0.key) < mix($1.key) }
        shown = min(shown + 10, feed.count)
    }

    // MARK: Building

    private func build() {
        let all = Kitchen.candidates()
        let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var context = RankContext()
        context.profile = People.profile()
        context.pantry = Kitchen.pantrySignals()
        context.cuisines = settings.customizationPreferences.choices["cuisines"] ?? []
        context.highProtein = People.me().wantsHighProtein
        let ranked = Recommender.rank(all.map(\.facts), context)
        // Shuffle within bands of eight: still best-first, but a different mix on every visit.
        let ordered = stride(from: 0, to: ranked.count, by: 8).flatMap { start in
            ranked[start..<min(start + 8, ranked.count)].sorted { mix($0.id) < mix($1.id) }
        }
        let recipes = ordered.compactMap { byKey[$0.id] }

        var built: [Row] = []
        func add(_ id: String, _ title: String, _ subtitle: String?, _ list: [Recipe]) {
            let list = Array(list.prefix(12))
            if list.count >= 3 { built.append(Row(id: id, title: title, subtitle: subtitle, recipes: list)) }
        }

        let cooked = all.filter { $0.isSaved && $0.cookedCount > 0 }.sorted { ($0.lastCookedAt ?? .distantPast) > ($1.lastCookedAt ?? .distantPast) }
        if let last = cooked.first {
            let words = Set(last.facts.ingredientNames.map { FoodText.normalize($0) })
            let similar = recipes.filter { recipe in
                guard recipe.key != last.key else { return false }
                if let cuisine = last.cuisine, !cuisine.isEmpty, recipe.cuisine == cuisine { return true }
                return Set(recipe.facts.ingredientNames.map { FoodText.normalize($0) }).intersection(words).count >= 3
            }
            add("because", Lang.text("Because you cooked %@").replacingOccurrences(of: "%@", with: last.displayTitle), nil, similar)
        }

        let liked = all.filter { $0.isSaved && ($0.isFavorite || $0.cookedCount > 0) }.compactMap(\.cuisine).filter { !$0.isEmpty }
        if let cuisine = Dictionary(grouping: liked, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            add("cuisine", Lang.text("More %@ dishes").replacingOccurrences(of: "%@", with: cuisine), Lang.text("You keep coming back to these"),
                recipes.filter { $0.cuisine == cuisine && $0.cookedCount == 0 })
        }

        let pantryPicks = ranked.filter { $0.have.count >= 2 && $0.missing.count <= 2 }
            .sorted { $0.missing.count < $1.missing.count }.compactMap { byKey[$0.id] }
        add("pantry", Lang.text("Cook with what you have"), Lang.text("Two things or fewer to buy"), pantryPicks)

        let usual = personal.habits.usualMinutes(at: .now) ?? 30
        add("quick", Lang.text("Ready in %lld minutes").replacingOccurrences(of: "%lld", with: "\(max(usual, 20))"), nil,
            recipes.filter { $0.minutes > 0 && $0.minutes <= max(usual, 20) })

        add("saved", Lang.text("Saved, not cooked yet"), Lang.text("From your cookbook"),
            recipes.filter { $0.isSaved && $0.cookedCount == 0 })

        add("favourites", Lang.text("Your favourites"), nil, recipes.filter(\.isFavorite))

        rows = built.sorted { mix($0.id) < mix($1.id) }
        let inRows = Set(built.flatMap { $0.recipes.prefix(4).map(\.key) })
        feed = recipes.filter { !inRows.contains($0.key) }
        shown = min(10, feed.count)
        nextKitchen = 0
    }

    /// Stable per-visit shuffle (String.hashValue isn't stable across launches).
    private func mix(_ text: String) -> UInt64 {
        var hash: UInt64 = 5381 &+ UInt64(truncatingIfNeeded: seed) &* 2_654_435_761
        for byte in text.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return hash
    }
}
