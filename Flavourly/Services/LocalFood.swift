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
        var region: String?
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

    /// Set through `choose(_:)` (a manual pick) or `followLocation()`; changing it reloads the dishes.
    @Published private(set) var country: String
    /// State, province or city from the phone's location ("Gujarat"); nil for the whole country.
    @Published private(set) var region: String?
    /// True until the cook picks a country by hand: the place then follows the phone's location.
    @Published private(set) var followsLocation: Bool

    private func move(to country: String, region: String?) {
        guard country != self.country || region != self.region else { return }
        self.country = country
        self.region = region
        UserDefaults.standard.set(country, forKey: Self.countryKey)
        UserDefaults.standard.set(region, forKey: Self.regionKey)
        catalog = nil
        dishes = []
        problem = nil
        RankContext.localCuisine = nil
        restoreCached()
        Task { await load() }
    }

    /// A country picked by hand: stays until the cook switches back to their location.
    func choose(_ country: String) {
        followsLocation = false
        UserDefaults.standard.set(false, forKey: Self.autoKey)
        move(to: country, region: nil)
    }

    /// Uses the phone's location (asking once). Returns false when location is off, keeping the current place.
    @discardableResult
    func followLocation() async -> Bool {
        followsLocation = true
        UserDefaults.standard.set(true, forKey: Self.autoKey)
        guard let place = await LocationService.shared.currentPlace(), Self.countries.contains(place.country) else { return false }
        move(to: place.country, region: place.region)
        return true
    }

    /// At launch: refresh from the location if the cook hasn't picked a country by hand.
    func refreshPlace() async {
        if followsLocation { await followLocation() }
    }

    /// Cuisines people cook everywhere; other foreign cuisines only show when the cook picked them.
    static let everywhere = ["Italian", "American", "Mediterranean"]
    static let fallbackStaples = ["Rice", "Eggs", "Onion", "Tomato", "Potato", "Garlic", "Ginger", "Milk", "Butter", "Flour",
                                  "Lentils", "Chickpeas", "Chicken", "Yogurt", "Cheese", "Bread", "Pasta", "Spinach", "Carrot", "Lemon"]
    static let fallbackCravings = ["Something spicy", "Comfort food", "Healthy", "Eggs", "Rice bowl", "Soup", "Pasta", "Sweet"]

    private static let countryKey = "localFoodCountry"
    private static let regionKey = "localFoodRegion"
    private static let autoKey = "localFoodFollowsLocation"
    private static let notCountries: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ", "AQ", "BV", "HM", "TF", "UM", "CP", "DG", "EA", "IC", "TA", "AC"]

    /// Every country a cook can pick, sorted by its name in the phone's language.
    static let countries: [String] = Locale.Region.isoRegions.map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) && !notCountries.contains($0) && Locale.current.localizedString(forRegionCode: $0) != nil }
        .sorted { name(for: $0).localizedCompare(name(for: $1)) == .orderedAscending }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.countryKey) ?? Locale.current.region?.identifier ?? "US"
        country = Self.countries.contains(saved) ? saved : "US"
        region = UserDefaults.standard.string(forKey: Self.regionKey)
        followsLocation = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
        restoreCached()
    }

    var countryName: String { Self.name(for: country) }
    /// The region the dishes shown are really for: the server may answer with the whole country.
    var shownRegion: String? { catalog == nil ? region : catalog?.region }
    /// "Gujarat" when the dishes are for a region, otherwise the country.
    var placeName: String { shownRegion ?? countryName }
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

    private var cacheKey: String { ResponseCache.key(Apis.discover, ["country": country, "region": region ?? ""]) }

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

    private var reloadAfterLoading = false
    private var paintingPhotos: Bool { catalog?.dishes.contains { $0.imageURL == nil } ?? false }
    private var photoChecks = 0

    func load() async {
        // A place change while a load runs (e.g. the location arrives at launch): load again right after.
        guard !isLoading else { reloadAfterLoading = true; return }
        let code = country, place = region
        isLoading = true
        problem = nil
        defer {
            isLoading = false
            if reloadAfterLoading {
                reloadAfterLoading = false
                Task { await load() }
            }
        }
        struct Body: Encodable { let country: String; let region: String? }
        do {
            var fresh: Catalog
            do {
                fresh = try await APIClient.shared.post(Apis.discover, Body(country: code, region: place), as: Catalog.self)
            } catch where place != nil {
                // A region the server can't build right now: the whole country's dishes are still local.
                fresh = try await APIClient.shared.post(Apis.discover, Body(country: code, region: nil), as: Catalog.self)
            }
            guard code == country, place == region else { return }
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
            guard code == country, place == region, catalog == nil else { return }
            problem = (error as? APIError) == .premiumRequired ? WorldKitchens.premiumNote : error.localizedDescription
        }
    }

    private func apply(_ catalog: Catalog) {
        self.catalog = catalog
        RankContext.localCuisine = catalog.cuisine
        dishes = Library.shared.add(catalog.dishes)
    }

    /// Built-in and explored dishes from another cuisine show only when the cook picked it (or "Any cuisine"):
    /// local dishes first, plus the few cuisines cooked everywhere. Holds before the country's list has loaded too.
    func allows(_ recipe: Recipe) -> Bool {
        guard recipe.isCurated else { return true }
        if let id = recipe.remoteID, id.hasPrefix("local-") { return id.hasPrefix("local-\(country.lowercased())-") }
        guard let cuisine = recipe.cuisine else { return false }
        let picked = SettingsManager.shared.customizationPreferences.choices["cuisines"] ?? []
        if picked.contains("Any cuisine") { return true }
        let home = [catalog?.cuisine, Self.cuisine(of: country)].compactMap { $0 }
        return (home + picked + Self.everywhere).contains { $0.caseInsensitiveCompare(cuisine) == .orderedSame }
    }

    /// The built-in recipes' cuisines for the countries that cook them, before the server's list arrives.
    static func cuisine(of country: String) -> String? {
        switch country {
        case "IN", "PK", "BD", "NP", "LK": "Indian"
        case "CN", "TW", "HK", "SG", "MY": "Chinese"
        case "AE", "SA", "QA", "KW", "BH", "OM", "JO", "LB", "SY", "IQ", "EG", "IL", "PS", "MA", "TN", "DZ", "TR", "IR": "Middle Eastern"
        case "IT": "Italian"
        case "GR", "CY", "ES", "PT", "HR", "MT": "Mediterranean"
        case "US", "CA": "American"
        default: nil
        }
    }

    /// Local dishes that fit everyone's rules, minus what this cook has already made — a new trio each day.
    func untried(profile: FoodProfile, seed: Int, count: Int = 3) -> [Recipe] {
        let cooked = CoreDataManager.shared.fetch(Recipe.self, NSPredicate(format: "cookedCount > 0"))
        let cookedIDs = Set(cooked.compactMap(\.remoteID))
        let cookedTitles = Set(cooked.map { $0.displayTitle.lowercased() })
        let pool = (dishes.isEmpty ? Library.shared.recipes.filter(allows) : dishes).filter { recipe in
            recipe.cookedCount == 0 && !cookedIDs.contains(recipe.remoteID ?? "") && !cookedTitles.contains(recipe.displayTitle.lowercased())
                && Self.fits(recipe, profile)
        }
        return Array(pool.sorted { Self.mix($0.key, seed) < Self.mix($1.key, seed) }.prefix(count))
    }

    /// Shown without anyone asking for it, so even a "likely" allergen keeps a dish out.
    static func fits(_ recipe: Recipe, _ profile: FoodProfile) -> Bool {
        let check = FoodRules.check(ingredients: recipe.checkLines, profile: profile, carbsPerServing: recipe.carbs)
        return !check.isBlocked && check.allergenIssues.isEmpty && !check.hasDislike
    }

    /// Stable shuffle (String.hashValue changes every launch).
    private static func mix(_ text: String, _ seed: Int) -> UInt64 {
        var hash: UInt64 = 5381 &+ UInt64(truncatingIfNeeded: seed) &* 2_654_435_761
        for byte in text.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return hash
    }
}
