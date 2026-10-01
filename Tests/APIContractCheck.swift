import Foundation

// Contract check: calls a running Flavourly API with the same JSON the app sends and decodes every
// answer with the app's own RecipeDraft model (lenient decoder, nutrition, flags) and Validate rules.
// Run (API on :8080):
//   swiftc -parse-as-library Flavourly/Domain/*.swift Flavourly/Data/RecipeDraft.swift Tests/APIContractCheck.swift -o /tmp/contract && /tmp/contract
@main
struct APIContractCheck {
    static let base = URL(string: ProcessInfo.processInfo.environment["API_URL"] ?? "http://127.0.0.1:8080")!
    static var failures = 0

    // Mirrors of the small reply types in Services/AIService.swift.
    struct Token: Decodable { let token: String }
    struct Rules: Encodable { var allergies = ["Peanuts"], diets = ["Vegetarian"], dislikes = ["mushrooms"], mildOnly = false }
    struct Option: Decodable { let name: String; let amount: String; let why: String; let flavour: String?; let tag: String? }
    struct Idea: Decodable { let recipe: RecipeDraft; let reason: String? }
    struct Pick: Decodable { let date: String; let slot: String; let recipeId: String; let reason: String? }
    struct LinkReply: Decodable { let recipe: RecipeDraft; let via: String?; let notes: [String]? }
    struct Failure: Decodable { let error: String? }
    struct Empty: Codable {}

    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        if condition { print("✔ \(message)") } else { failures += 1; print("✘ line \(line): \(message)") }
    }

    static func post<Body: Encodable>(_ path: String, _ body: Body, token: String? = nil) async throws -> (Int, Data) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1.0", forHTTPHeaderField: "X-App-Version")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            print("   decode error: \(error)\n   body: \(String(data: data, encoding: .utf8)?.prefix(400) ?? "")")
            return nil
        }
    }

    /// The app validates drafts before saving; server output must pass the same rules.
    static func passesAppValidation(_ draft: RecipeDraft) -> Bool {
        let clean = draft.sanitized()
        let fields = RecipeDraftFields(title: clean.title, summary: clean.summary ?? "", cuisine: clean.cuisine ?? "",
                                       servings: min(clean.servings, 40), minutes: clean.prepMinutes + clean.cookMinutes, tags: clean.tags,
                                       ingredients: clean.ingredients.map(\.text), steps: clean.steps.map(\.text))
        let problem = Validate.recipe(fields)
        if let problem { print("   app validation: \(problem)") }
        return problem == nil
    }

    static func main() async {
        do {
            struct Device: Encodable { let installID: String; let platform: String; let appVersion: String }
            let (status, data) = try await post("v1/devices", Device(installID: UUID().uuidString, platform: "ios", appVersion: "1.0"))
            guard status == 200, let token = decode(Token.self, data)?.token else {
                print("✘ could not register (\(status)) — is the API running at \(base)?")
                exit(1)
            }
            check(token.count == 43, "device token issued")

            struct Extract: Encodable { let text: String; let kind: String; let sourceURL: String?; let rules: Rules }
            let text = "Masala omelette\nIngredients\n- 3 eggs\n- 1 onion, finely chopped\n- 1 green chilli\nMethod\n1. Whisk the eggs\n2. Cook for 3 min"
            var (code, body) = try await post("v1/ai/extract", Extract(text: text, kind: "ocr", sourceURL: nil, rules: Rules()), token: token)
            struct ExtractReply: Decodable { let recipe: RecipeDraft }
            if let draft = decode(ExtractReply.self, body)?.recipe {
                check(code == 200 && draft.title == "Masala omelette", "extract → RecipeDraft: \(draft.title)")
                check(draft.ingredients.count == 3 && draft.ingredients[0].quantity == 3 && draft.ingredients[0].name == "eggs", "ingredients keep server-parsed amounts")
                check(draft.steps.count == 2 && draft.steps[1].timerSeconds == 180, "steps with timers")
                check(draft.nutrition?.calories ?? 0 > 0, "nutrition decodes (all keys present)")
                check(draft.method == "scan", "method set for scans")
                check(passesAppValidation(draft), "server recipe passes the app's validators")
            } else { check(false, "extract decodes") }

            struct Swap: Encodable { let ingredient: String; let recipeTitle: String; let otherIngredients: [String]; let rules: Rules }
            (code, body) = try await post("v1/ai/substitutes", Swap(ingredient: "200 ml cream", recipeTitle: "Pasta", otherIngredients: ["pasta"], rules: Rules()), token: token)
            struct SwapReply: Decodable { let options: [Option] }
            let options = decode(SwapReply.self, body)?.options ?? []
            check(code == 200 && options.count == 2 && options.allSatisfy { !$0.name.isEmpty && !$0.why.isEmpty }, "substitutes decode as SubstituteOption")

            struct CookNow: Encodable { let minutes: Int?; let craving: String; let pantry: [String]; let okToBuy: Int; let servings: Int; let rules: Rules; let avoidTitles: [String] }
            (code, body) = try await post("v1/ai/cook-now", CookNow(minutes: 30, craving: "rice", pantry: ["rice", "eggs"], okToBuy: 2, servings: 2, rules: Rules(), avoidTitles: []), token: token)
            struct IdeasReply: Decodable { let ideas: [Idea] }
            let ideas = decode(IdeasReply.self, body)?.ideas ?? []
            check(code == 200 && !ideas.isEmpty && ideas.allSatisfy { $0.recipe.minutes <= 35 && !$0.recipe.ingredients.isEmpty }, "Cook Now ideas decode (\(ideas.map(\.recipe.title)))")
            check(ideas.allSatisfy { passesAppValidation($0.recipe) }, "AI ideas pass the app's validators")
            (code, body) = try await post("v1/ai/cook-now", CookNow(minutes: nil, craving: "", pantry: [], okToBuy: 2, servings: 2, rules: Rules(), avoidTitles: []), token: token)
            check(code == 200, "Cook Now accepts a missing time limit (nil minutes is omitted by JSONEncoder)")

            struct Slot: Encodable { let date: String; let slot: String; let candidates: [String] }
            struct Candidate: Encodable { let id: String; let title: String; let minutes: Int; let slots: [String]; let cuisine: String?; let protein: Int; let reasons: [String] }
            struct Plan: Encodable { let slots: [Slot]; let candidates: [Candidate]; let preferences: [String]; let rules: Rules }
            (code, body) = try await post("v1/ai/plan", Plan(slots: [Slot(date: "2026-10-06", slot: "dinner", candidates: ["dal", "pasta"])],
                                                           candidates: [Candidate(id: "dal", title: "Dal", minutes: 30, slots: ["dinner"], cuisine: nil, protein: 18, reasons: []),
                                                                        Candidate(id: "pasta", title: "Pasta", minutes: 20, slots: ["dinner"], cuisine: "Italian", protein: 12, reasons: [])],
                                                           preferences: ["High protein"], rules: Rules()), token: token)
            struct PlanReply: Decodable { let picks: [Pick] }
            let picks = decode(PlanReply.self, body)?.picks ?? []
            check(code == 200 && picks.count == 1 && picks[0].recipeId == "dal", "plan picks decode and stay inside the shortlist")

            struct Link: Encodable { let url: String; let pageText: String?; let rules: Rules }
            (code, body) = try await post("v1/imports", Link(url: "https://example-blog.com/stew?utm_source=x", pageText: "Lamb stew\nIngredients\n500 g lamb\n2 carrots\nMethod\n1. Brown the lamb\n2. Stew for 90 min", rules: Rules()), token: token)
            if let reply = decode(LinkReply.self, body) {
                check(code == 200 && reply.recipe.title == "Lamb stew" && reply.via == "page", "link import with page text → LinkReply")
                check(reply.recipe.sourceURL == "https://example-blog.com/stew", "tracking parameters removed from the source link")
            } else { check(false, "link import decodes") }

            struct Image: Encodable { let title: String; let description: String? }
            (code, body) = try await post("v1/images/recipe", Image(title: "Masala omelette", description: nil), token: token)
            struct ImageReply: Decodable { let url: String }
            check(code == 200 && (decode(ImageReply.self, body)?.url.hasSuffix(".jpg") ?? false), "AI photo URL decodes")

            (code, body) = try await post("v1/ai/substitutes", Swap(ingredient: "", recipeTitle: "x", otherIngredients: [], rules: Rules()), token: token)
            check(code == 400 && !(decode(Failure.self, body)?.error ?? "").isEmpty, "validation errors carry a readable `error` message")

            (code, _) = try await post("v1/ai/plan", Empty(), token: "not-a-token")
            check(code == 401, "bad token → 401 (the app re-registers)")

            (code, body) = try await post("v1/devices/erase", Empty(), token: token)
            check(code == 200 && decode(Empty.self, body) != nil, "erase answers {}")
        } catch {
            print("✘ request failed: \(error)")
            failures += 1
        }
        print(failures == 0 ? "APIContractCheck passed" : "APIContractCheck: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
