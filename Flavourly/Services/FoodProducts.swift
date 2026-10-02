import Foundation

/// Packaged food by barcode from Open Food Facts (free, open data, ODbL — the app shows the credit).
/// Called straight from the phone: each user has their own rate limit, and no key is needed.
struct FoodProduct: Codable, Equatable {
    var barcode: String
    var name: String
    var brand: String?
    var quantity: String?
    var allergens: [String]
    var traces: [String]
    var ingredients: String?
    var nutriScore: String?
    var imageURL: String?

    /// "Amul Butter" — brand first only when the name doesn't already contain it.
    var displayName: String {
        guard let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) else { return name }
        return "\(brand) \(name)"
    }

    /// Everything the household rules should see: declared allergens, "may contain" traces, ingredient list.
    var checkLines: [String] {
        allergens + traces.map { "may contain \($0)" } + (ingredients.map { [$0] } ?? [])
    }
}

enum OpenFoodFacts {
    enum Failure: LocalizedError {
        case invalid(String), notFound, offline
        var errorDescription: String? {
            switch self {
            case .invalid(let message): message
            case .notFound: "This product isn't in Open Food Facts yet. Add it by name instead."
            case .offline: "Couldn't reach Open Food Facts. Check your connection and try again."
            }
        }
    }

    static func product(barcode raw: String) async throws -> FoodProduct {
        let check = Validate.barcode(raw)
        guard let code = check.value else { throw Failure.invalid(check.message ?? "That isn't a barcode") }
        let key = "off:\(code)"
        if let hit = ResponseCache.shared.value(FoodProduct.self, for: key) { return hit }

        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,generic_name,brands,quantity,allergens_tags,traces_tags,ingredients_text,nutriscore_grade,image_front_small_url")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Flavourly/\(AppInfo.version) (iOS; https://flavourly.dakshyaminfotech.store)", forHTTPHeaderField: "User-Agent")

        struct Reply: Decodable {
            struct Product: Decodable {
                let product_name: String?, generic_name: String?, brands: String?, quantity: String?
                let allergens_tags: [String]?, traces_tags: [String]?, ingredients_text: String?
                let nutriscore_grade: String?, image_front_small_url: String?
            }
            let status: Int?
            let product: Product?
        }
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) } catch { throw Failure.offline }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.status == 1, let product = reply.product else {
            throw Failure.notFound
        }
        let name = Sanitize.text(product.product_name ?? product.generic_name ?? "")
        guard !name.isEmpty else { throw Failure.notFound }
        let found = FoodProduct(
            barcode: code,
            name: String(name.prefix(Validate.Limit.itemName)),
            brand: product.brands?.split(separator: ",").first.map { Sanitize.text(String($0)) },
            quantity: product.quantity.map { Sanitize.text($0.replacingOccurrences(of: "℮", with: "")) },
            allergens: tags(product.allergens_tags),
            traces: tags(product.traces_tags),
            ingredients: product.ingredients_text.map { String(Sanitize.text($0).prefix(2_000)) },
            nutriScore: product.nutriscore_grade.flatMap { ["a", "b", "c", "d", "e"].contains($0) ? $0.uppercased() : nil },
            imageURL: product.image_front_small_url.flatMap { Validate.link($0).url?.absoluteString }
        )
        ResponseCache.shared.store(found, for: key, ttl: 30 * 86_400)
        return found
    }

    /// "en:sesame-seeds" → "sesame seeds" (other languages' tags are kept as words too).
    private static func tags(_ list: [String]?) -> [String] {
        (list ?? []).map { tag in
            let word = tag.split(separator: ":").last.map(String.init) ?? tag
            return word.replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "crustaceans", with: "shellfish crustaceans")
                .replacingOccurrences(of: "molluscs", with: "shellfish molluscs")
                .replacingOccurrences(of: "soybeans", with: "soy")
        }
    }
}
