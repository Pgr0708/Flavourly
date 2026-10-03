import Foundation

/// Search any dish in the world: name suggestions as you type (local dishes first), the recipe from the
/// shared library (found once on the server, then reused by everyone), and recipe videos.
@MainActor
enum DishSearch {
    struct Suggestion: Codable, Hashable, Identifiable {
        var name: String
        var region: String?
        var id: String { name }
    }

    struct Video: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var channel: String
        var thumbnail: String?
        var url: String
    }

    private static var suggestions: [String: [Suggestion]] = [:]

    static func suggest(_ text: String) async -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        if let hit = suggestions[query.lowercased()] { return hit }
        struct Body: Encodable { let q: String; let country: String; let region: String? }
        struct Reply: Decodable { let suggestions: [Suggestion] }
        let local = LocalFood.shared
        guard let reply = try? await APIClient.shared.post(Apis.dishSuggest, Body(q: String(query.prefix(60)), country: local.country, region: local.region),
                                                          as: Reply.self) else { return [] }
        suggestions[query.lowercased()] = reply.suggestions
        return reply.suggestions
    }

    /// The dish as a recipe the app can open, save and cook.
    static func find(_ name: String) async throws -> Recipe {
        struct Body: Encodable { let name: String; let country: String; let region: String? }
        struct Reply: Decodable { let recipe: RecipeDraft; var live: Bool? }
        let local = LocalFood.shared
        let key = ResponseCache.key(Apis.dishFind, ["name": name.lowercased()])
        let draft: RecipeDraft
        if let hit = ResponseCache.shared.value(RecipeDraft.self, for: key) {
            draft = hit
        } else {
            let reply = try await APIClient.shared.post(Apis.dishFind, Body(name: String(name.prefix(80)), country: local.country, region: local.region),
                                                        as: Reply.self)
            draft = reply.recipe
            // Live recipes (Spoonacular) may only be kept for an hour under their terms.
            ResponseCache.shared.store(draft, for: key, ttl: reply.live == true ? 3_600 : 30 * 86_400)
        }
        Personalizer.shared.remember(name)
        guard let recipe = Library.shared.add([draft]).first else { throw APIError.invalidResponse }
        return recipe
    }

    static func videos(for title: String) async -> (videos: [Video], search: URL?) {
        struct Body: Encodable { let title: String }
        struct Reply: Codable { let videos: [Video]; let searchURL: String }
        let body = Body(title: String(title.prefix(120)))
        let key = ResponseCache.key(Apis.videos, body)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return (hit.videos, URL(string: hit.searchURL)) }
        guard let reply = try? await APIClient.shared.post(Apis.videos, body, as: Reply.self) else {
            let fallback = "https://www.youtube.com/results?search_query=" + (title + " recipe").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).orEmpty
            return ([], URL(string: fallback))
        }
        ResponseCache.shared.store(reply, for: key, ttl: 7 * 86_400)
        return (reply.videos, URL(string: reply.searchURL))
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
