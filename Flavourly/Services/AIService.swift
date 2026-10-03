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
        let body = Body(text: String(text.prefix(Validate.Limit.pasted)), kind: kind, sourceURL: sourceURL, rules: .current())
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
        // Clipped to the server's limits: one long line must not fail the whole request.
        let others = recipe.checkLines.filter { $0 != ingredient }.prefix(Validate.Limit.ingredients).map { String($0.prefix(Validate.Limit.ingredient)) }
        let body = Body(ingredient: String(ingredient.prefix(Validate.Limit.ingredient)), recipeTitle: String(recipe.displayTitle.prefix(Validate.Limit.title)),
                        otherIngredients: Array(others), rules: .current(for: eaters))
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

    // MARK: Nutrition

    /// Verified per-serving nutrition (USDA FoodData Central, then Spoonacular), or nil when too few lines match.
    static func nutrition(lines: [String], servings: Int) async throws -> DraftNutrition? {
        struct Body: Encodable { let lines: [String]; let servings: Int }
        struct Reply: Codable { let nutrition: DraftNutrition? }
        let body = Body(lines: Array(lines.map { String($0.prefix(Validate.Limit.ingredient)) }.prefix(Validate.Limit.ingredients)),
                        servings: min(100, max(1, servings)))
        let key = ResponseCache.key(Apis.nutrition, body)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return hit.nutrition }
        let reply = try await APIClient.shared.post(Apis.nutrition, body, as: Reply.self)
        ResponseCache.shared.store(reply, for: key, ttl: 30 * 86_400)
        return reply.nutrition
    }

    // MARK: Images

    /// A free, credited photo for a saved recipe, or nil when none matches (the server never uses GPT here).
    static func freePhotoURL(title: String) async throws -> String? {
        struct Body: Encodable { let title: String; let freeOnly = true }
        struct Reply: Codable { let url: String }
        do {
            return try await APIClient.shared.post(Apis.recipeImage, Body(title: String(title.prefix(Validate.Limit.title))), as: Reply.self).url
        } catch APIError.server {
            return nil // 404 "no free photo yet", or a title the server rejects
        }
    }

    static func recipeImageURL(title: String, summary: String?) async throws -> String {
        struct Body: Encodable { let title: String; let description: String? }
        struct Reply: Codable { let url: String }
        let body = Body(title: String(title.prefix(Validate.Limit.title)), description: summary.map { String($0.prefix(Validate.Limit.summary)) })
        let key = ResponseCache.key(Apis.recipeImage, body)
        if let hit = ResponseCache.shared.value(Reply.self, for: key) { return hit.url }
        let reply = try await APIClient.shared.post(Apis.recipeImage, body, as: Reply.self)
        ResponseCache.shared.store(reply, for: key, ttl: 30 * 86_400)
        return reply.url
    }
}
