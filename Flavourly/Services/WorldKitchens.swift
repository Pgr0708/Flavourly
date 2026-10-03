import Foundation

/// The world explorer: any country's popular home dishes and its famous regional cuisines.
/// Browsing never changes the cook's own country — explored dishes stay out of For You and plans.
@MainActor
enum WorldKitchens {
    struct Region: Codable, Hashable, Identifiable {
        var name: String
        var about: String
        var signature: String
        var imageURL: String?
        var id: String { name }
    }

    struct Regions: Codable {
        var country: String
        var name: String
        var regions: [Region]
    }

    static let premiumNote = "Nobody has opened this place yet. Premium cooks unlock new places with AI — after that they're free for everyone."

    /// Kitchens most people want to explore, each shown with a photo of its most famous dish.
    static let featured: [(country: String, dish: String)] = [
        ("IT", "Margherita pizza"), ("IN", "Butter chicken"), ("MX", "Tacos al pastor"), ("JP", "Sushi"),
        ("TH", "Pad thai"), ("CN", "Kung pao chicken"), ("FR", "Ratatouille"), ("ES", "Paella"),
        ("GR", "Moussaka"), ("TR", "Baklava"), ("LB", "Tabbouleh"), ("KR", "Bibimbap"),
        ("VN", "Pho"), ("US", "Cheeseburger"), ("MA", "Tagine"), ("PE", "Ceviche"),
        ("BR", "Feijoada"), ("NG", "Jollof rice"), ("ET", "Doro wat"), ("GB", "Fish and chips"),
    ]

    static func regions(for country: String) async throws -> Regions {
        struct Body: Encodable { let country: String }
        let key = ResponseCache.key(Apis.regions, Body(country: country))
        if let hit = ResponseCache.shared.value(Regions.self, for: key) { return hit }
        let fresh = try await APIClient.shared.post(Apis.regions, Body(country: country), as: Regions.self)
        // Signature photos arrive in the background: keep for a day until they're all there, then a month.
        ResponseCache.shared.store(fresh, for: key, ttl: fresh.regions.allSatisfy { $0.imageURL != nil } ? 30 * 86_400 : 3_600)
        return fresh
    }

    /// A country's (or one region's) dishes as recipes the app can open, save and cook.
    static func dishes(country: String, region: String?) async throws -> [Recipe] {
        struct Body: Encodable { let country: String; let region: String? }
        let body = Body(country: country, region: region)
        let key = ResponseCache.key(Apis.discover, ["country": country, "region": region ?? ""])
        let catalog: LocalFood.Catalog
        if let hit = ResponseCache.shared.value(LocalFood.Catalog.self, for: key), hit.dishes.allSatisfy({ $0.imageURL != nil }) {
            catalog = hit
        } else {
            catalog = try await APIClient.shared.post(Apis.discover, body, as: LocalFood.Catalog.self)
            ResponseCache.shared.store(catalog, for: key, ttl: catalog.dishes.allSatisfy { $0.imageURL != nil } ? 14 * 86_400 : 600)
        }
        return Library.shared.add(catalog.dishes)
    }

    /// A free, credited photo of a famous dish (cached on the server for everyone and here for a month).
    static func photo(of dish: String) async -> String? {
        let key = ResponseCache.key("photo", ["dish": dish])
        if let hit = ResponseCache.shared.value(String.self, for: key) { return hit }
        guard let url = try? await AIService.freePhotoURL(title: dish) else { return nil }
        ResponseCache.shared.store(url, for: key, ttl: 30 * 86_400)
        return url
    }
}
