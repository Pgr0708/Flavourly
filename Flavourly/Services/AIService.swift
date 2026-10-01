import Foundation

/// Hard rules sent with every AI request. The server prompts with them AND the app
/// re-checks every answer with FoodRules — AI never gets the last word on safety.
struct RulesPayload: Codable {
    var allergies: [String]
    var diets: [String]
    var dislikes: [String]
    var mildOnly: Bool

    @MainActor
    static func current(for ids: [String]? = nil) -> RulesPayload {
        let people = People.all().filter { ids?.contains($0.id) ?? true }
        return RulesPayload(
            allergies: Array(Set(people.flatMap(\.allergies))).sorted(),
            diets: Array(Set(people.flatMap(\.diets))).sorted(),
            dislikes: Array(Set(people.flatMap(\.dislikes))).sorted(),
            mildOnly: people.contains(where: \.mildOnly)
        )
    }
}

struct SubstituteOption: Codable, Identifiable, Equatable {
    var id: String { name + amount }
    var name: String
    var amount: String
    var why: String
    var flavour: String?
    var texture: String?
    var nutrition: String?
    var tag: String?
}

struct CookNowIdea: Codable, Identifiable {
    var id: String { recipe.title }
    var recipe: RecipeDraft
    var reason: String?
}

@MainActor
enum AIService {
    // MARK: Import helpers

    static func extract(text: String, kind: String, sourceURL: String? = nil) async throws -> RecipeDraft {
        struct Body: Encodable { let text: String; let kind: String; let sourceURL: String?; let rules: RulesPayload }
        struct Reply: Codable { let recipe: RecipeDraft }
        let body = Body(text: String(text.prefix(12_000)), kind: kind, sourceURL: sourceURL, rules: .current())
        let key = ResponseCache.key(Apis.extract, body)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return hit.recipe }
        let reply = try await APIClient.shared.post(Apis.extract, body, as: Reply.self)
        ResponseCache.shared.store(reply, for: key, ttl: 7 * 86_400)
        return reply.recipe
    }

    struct LinkReply: Decodable {
        let recipe: RecipeDraft
        let via: String?
        let notes: [String]?
    }

    static func importLink(_ url: URL, pageText: String? = nil) async throws -> LinkReply {
        struct Body: Encodable { let url: String; let pageText: String?; let rules: RulesPayload }
        return try await APIClient.shared.post(Apis.importLink, Body(url: url.absoluteString, pageText: pageText, rules: .current()), as: LinkReply.self)
    }

    // MARK: Swaps

    static func substitutes(for ingredient: String, in recipe: Recipe, eaters: [String]? = nil) async throws -> [SubstituteOption] {
        struct Body: Encodable { let ingredient: String; let recipeTitle: String; let otherIngredients: [String]; let rules: RulesPayload }
        struct Reply: Codable { let options: [SubstituteOption] }
        let others = recipe.checkLines.filter { $0 != ingredient }
        let body = Body(ingredient: ingredient, recipeTitle: recipe.displayTitle, otherIngredients: others, rules: .current(for: eaters))
        let key = ResponseCache.key(Apis.substitutes, body)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return hit.options }
        let reply = try await APIClient.shared.post(Apis.substitutes, body, as: Reply.self)
        Usage.record(.aiSwap)
        ResponseCache.shared.store(reply, for: key, ttl: 30 * 86_400)
        return reply.options
    }

    // MARK: Cook Now

    struct CookNowRequest: Encodable {
        let minutes: Int?
        let craving: String
        let pantry: [String]
        let okToBuy: Int
        let servings: Int
        let rules: RulesPayload
        let avoidTitles: [String]
        /// ISO country code: ideas lean to dishes cooked there.
        let country: String?
    }

    static func cookNowIdeas(_ request: CookNowRequest) async throws -> [CookNowIdea] {
        struct Reply: Codable { let ideas: [CookNowIdea] }
        let key = ResponseCache.key(Apis.cookNow, request)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return hit.ideas }
        let reply = try await APIClient.shared.post(Apis.cookNow, request, as: Reply.self)
        Usage.record(.aiIdeas)
        ResponseCache.shared.store(reply, for: key, ttl: 6 * 3600)
        return reply.ideas
    }

    // MARK: Planner

    struct PlanCandidate: Encodable {
        let id: String
        let title: String
        let minutes: Int
        let slots: [String]
        let cuisine: String?
        let protein: Int
        let reasons: [String]
    }

    struct PlanSlotRequest: Encodable {
        let date: String
        let slot: String
        let candidates: [String]
    }

    struct PlanRequest: Encodable {
        let slots: [PlanSlotRequest]
        let candidates: [PlanCandidate]
        let preferences: [String]
        let rules: RulesPayload
    }

    struct PlanChoice: Decodable {
        let date: String
        let slot: String
        let recipeId: String
        let reason: String?
    }

    /// Never cached: asking again should give a fresh week.
    static func plan(_ request: PlanRequest) async throws -> [PlanChoice] {
        struct Reply: Decodable { let picks: [PlanChoice] }
        let picks = try await APIClient.shared.post(Apis.plan, request, as: Reply.self).picks
        Usage.record(.aiPlan)
        return picks
    }

    // MARK: Images

    static func recipeImageURL(title: String, summary: String?) async throws -> String {
        struct Body: Encodable { let title: String; let description: String? }
        struct Reply: Codable { let url: String }
        let body = Body(title: title, description: summary)
        let key = ResponseCache.key(Apis.recipeImage, body)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return hit.url }
        let reply = try await APIClient.shared.post(Apis.recipeImage, body, as: Reply.self)
        ResponseCache.shared.store(reply, for: key, ttl: 30 * 86_400)
        return reply.url
    }
}
