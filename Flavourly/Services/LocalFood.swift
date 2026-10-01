import CoreData
import Foundation
internal import Combine

/// Popular home dishes from the cook's country (the phone's region until they pick another).
/// The server builds one catalogue per country and shares it; here it is cached on disk, added to the
/// in-memory Library (so recipe pages, plans and For You just work) and used to keep ideas local.
@MainActor
final class LocalFood: ObservableObject {
    static let shared = LocalFood()

    struct Catalog: Codable, Equatable {
        var country: String
        var name: String
        var cuisine: String
        var staples: [String] = []
        var cravings: [String] = []
        var dishes: [RecipeDraft] = []
        var fetchedAt: Date?
    }

    @Published private(set) var catalog: Catalog?
    @Published private(set) var dishes: [Recipe] = []
    @Published private(set) var isLoading = false
    @Published private(set) var problem: String?

    @Published var country: String {
        didSet {
            guard country != oldValue else { return }
            UserDefaults.standard.set(country, forKey: Self.countryKey)
            catalog = nil
            dishes = []
            problem = nil
            RankContext.localCuisine = nil
            restoreCached()
            Task { await load() }
        }
    }

    /// Cuisines people cook everywhere; other foreign cuisines only show when the cook picked them.
    static let everywhere = ["Italian", "American", "Mediterranean"]
    static let fallbackStaples = ["Rice", "Eggs", "Onion", "Tomato", "Potato", "Garlic", "Ginger", "Milk", "Butter", "Flour",
                                  "Lentils", "Chickpeas", "Chicken", "Yogurt", "Cheese", "Bread", "Pasta", "Spinach", "Carrot", "Lemon"]
    static let fallbackCravings = ["Something spicy", "Comfort food", "Healthy", "Eggs", "Rice bowl", "Soup", "Pasta", "Sweet"]

    private static let countryKey = "localFoodCountry"
    private static let notCountries: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ", "AQ", "BV", "HM", "TF", "UM", "CP", "DG", "EA", "IC", "TA", "AC"]

    /// Every country a cook can pick, sorted by its name in the phone's language.
    static let countries: [String] = Locale.Region.isoRegions.map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) && !notCountries.contains($0) && Locale.current.localizedString(forRegionCode: $0) != nil }
        .sorted { name(for: $0).localizedCompare(name(for: $1)) == .orderedAscending }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.countryKey) ?? Locale.current.region?.identifier ?? "US"
        country = Self.countries.contains(saved) ? saved : "US"
        restoreCached()
    }

    var countryName: String { Self.name(for: country) }
    var flag: String { Self.flag(for: country) }
    var cuisine: String { catalog?.cuisine ?? countryName }
    var staples: [String] { catalog.map(\.staples).flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackStaples }
    var cravings: [String] {
        let local = catalog?.cravings ?? []
        return Array(NSOrderedSet(array: local + Self.fallbackCravings)) as? [String] ?? Self.fallbackCravings
    }

    static func name(for code: String) -> String { Locale.current.localizedString(forRegionCode: code) ?? code }

    static func flag(for code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }

    private var cacheKey: String { ResponseCache.key(Apis.discover, ["country": country]) }

    private func restoreCached() {
        if let cached = ResponseCache.shared.value(Catalog.self, for: cacheKey), cached.country == country { apply(cached) }
    }

    /// Refreshes every few days, and sooner while the server is still painting photos.
    func refreshIfNeeded() async {
        if let catalog, let fetched = catalog.fetchedAt {
            let age = Date.now.timeIntervalSince(fetched)
            if age < 3 * 86_400, !(paintingPhotos && age > 90) { return }
        }
        await load()
    }

    private var paintingPhotos: Bool { catalog?.dishes.contains { $0.imageURL == nil } ?? false }
    private var photoChecks = 0

    func load() async {
        guard !isLoading else { return }
        let code = country
        isLoading = true
        problem = nil
        defer { isLoading = false }
        struct Body: Encodable { let country: String }
        do {
            var fresh = try await APIClient.shared.post(Apis.discover, Body(country: code), as: Catalog.self)
            guard code == country else { return }
            fresh.fetchedAt = .now
            // Kept long so the section still works offline; refreshIfNeeded decides when to ask again.
            ResponseCache.shared.store(fresh, for: cacheKey, ttl: 60 * 86_400)
            apply(fresh)
            // The server paints one photo at a time; check back so they appear while the app is open.
            if paintingPhotos, photoChecks < 10 {
                photoChecks += 1
                Task {
                    try? await Task.sleep(for: .seconds(90))
                    await refreshIfNeeded()
                }
            }
        } catch {
            guard code == country, catalog == nil else { return }
            problem = error.localizedDescription
        }
    }

    private func apply(_ catalog: Catalog) {
        self.catalog = catalog
        RankContext.localCuisine = catalog.cuisine
        dishes = Library.shared.add(catalog.dishes)
    }

    /// Library recipes from another cuisine show only when the cook picked it (or "Any cuisine").
    func allows(_ recipe: Recipe) -> Bool {
        guard recipe.isCurated else { return true }
        if let id = recipe.remoteID, id.hasPrefix("local-") { return id.hasPrefix("local-\(country.lowercased())-") }
        guard let catalog, let cuisine = recipe.cuisine else { return true }
        let picked = SettingsManager.shared.customizationPreferences.choices["cuisines"] ?? []
        if picked.contains("Any cuisine") { return true }
        return ([catalog.cuisine] + picked + Self.everywhere).contains { $0.caseInsensitiveCompare(cuisine) == .orderedSame }
    }

    /// Local dishes that fit everyone's rules, minus what this cook has already made — a new trio each day.
    func untried(profile: FoodProfile, seed: Int, count: Int = 3) -> [Recipe] {
        let cooked = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "cookedCount > 0"))
        let cookedIDs = Set(cooked.compactMap(\.remoteID))
        let cookedTitles = Set(cooked.map { $0.displayTitle.lowercased() })
        let pool = (dishes.isEmpty ? Library.shared.recipes.filter(allows) : dishes).filter { recipe in
            recipe.cookedCount == 0 && !cookedIDs.contains(recipe.remoteID ?? "") && !cookedTitles.contains(recipe.displayTitle.lowercased())
                && !FoodRules.check(ingredients: recipe.checkLines, profile: profile).isBlocked
        }
        return Array(pool.sorted { Self.mix($0.key, seed) < Self.mix($1.key, seed) }.prefix(count))
    }

    /// Stable shuffle (String.hashValue changes every launch).
    private static func mix(_ text: String, _ seed: Int) -> UInt64 {
        var hash: UInt64 = 5381 &+ UInt64(truncatingIfNeeded: seed) &* 2_654_435_761
        for byte in text.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return hash
    }
}
