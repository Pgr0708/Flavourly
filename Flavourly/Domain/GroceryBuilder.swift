import Foundation

/// One ingredient needed by one planned meal, already scaled to what will be cooked.
struct GroceryInput {
    let recipeTitle: String
    let when: String
    let name: String
    let quantity: Double?
    let unit: String
}

struct PantryStock {
    let name: String
    let quantity: Double?
    let unit: String
}

struct GroceryLine: Identifiable, Equatable {
    struct Source: Equatable, Hashable {
        let recipe: String
        let when: String
        let amount: String
    }

    var id: String { key }
    let key: String
    var name: String
    /// Total needed across all meals, in `unit`. Nil when recipes gave no amount ("salt to taste").
    var quantity: Double?
    var unit: String
    var aisle: Aisle
    var sources: [Source]
    /// How much the pantry already covers, in `unit`. Nil when unknown.
    var pantryQuantity: Double?
    var inPantry: Bool
    var isStaple: Bool

    var toBuy: Double? {
        guard let quantity else { return nil }
        return max(0, quantity - (pantryQuantity ?? 0))
    }

    /// The pantry has it and either the amount is unknown or it covers everything.
    var coveredByPantry: Bool {
        guard inPantry else { return false }
        guard let quantity, let pantryQuantity else { return true }
        return pantryQuantity + 0.0001 >= quantity
    }
}

enum GroceryBuilder {
    static let staples: Set<String> = ["salt", "sea salt", "kosher salt", "black pepper", "pepper", "water", "ice", "hot water", "cold water"]

    /// You can't buy half an egg: countable things round up to whole items on the list
    /// (a hair over a whole number, e.g. 2.02 from scaling, stays 2). Pinches and dashes stay as they are.
    static func shoppable(_ quantity: Double, unit: String) -> Double {
        guard !["pinch", "dash", "handful", "sprig"].contains(unit) else { return quantity }
        return max(1, (quantity - 0.05).rounded(.up))
    }

    static func build(_ inputs: [GroceryInput], pantry: [PantryStock], system: UnitSystem = .metric) -> [GroceryLine] {
        struct Bucket {
            var name: String
            var family: Units.Family
            var unit: String
            var total: Double
            var hasAmount: Bool
            var sources: [GroceryLine.Source]
        }
        var buckets: [String: Bucket] = [:]
        var order: [String] = []

        for input in inputs {
            let nameKey = FoodText.key(input.name)
            guard !nameKey.isEmpty else { continue }
            let family = Units.family(input.unit)
            let tag: String
            switch family {
            case .mass: tag = "mass"
            case .volume: tag = "volume"
            case .other: tag = "u:" + input.unit
            }
            let key = nameKey + "|" + tag
            var bucket = buckets[key] ?? Bucket(name: displayName(input.name), family: family, unit: input.unit, total: 0, hasAmount: false, sources: [])
            if let quantity = input.quantity, quantity > 0 {
                bucket.total += family == .other ? quantity : (Units.toBase(quantity, unit: input.unit) ?? quantity)
                bucket.hasAmount = true
            }
            bucket.sources.append(.init(
                recipe: input.recipeTitle, when: input.when,
                amount: Amount.text(quantity: input.quantity, unit: input.unit, system: system)
            ))
            if buckets[key] == nil { order.append(key) }
            buckets[key] = bucket
        }

        let pantryByKey = Dictionary(pantry.map { (FoodText.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })

        return order.compactMap { key -> GroceryLine? in
            guard let bucket = buckets[key] else { return nil }
            let nameKey = String(key.split(separator: "|").first ?? "")
            var quantity: Double?
            var unit = bucket.unit
            if bucket.hasAmount {
                switch bucket.family {
                case .mass: (quantity, unit) = Amount.convert(bucket.total, unit: "g", to: system)
                case .volume: (quantity, unit) = Amount.convert(bucket.total, unit: "ml", to: system)
                case .other: quantity = Self.shoppable(bucket.total, unit: bucket.unit)
                }
            }

            let stock = pantryMatch(nameKey, in: pantryByKey)
            var covered: Double?
            if let stock, let stockQuantity = stock.quantity, stockQuantity > 0, quantity != nil {
                let stockFamily = Units.family(stock.unit)
                if stockFamily != .other, stockFamily == bucket.family,
                   let stockBase = Units.toBase(stockQuantity, unit: stock.unit), let factor = Units.base[unit]?.1 {
                    covered = stockBase / factor
                } else if stockFamily == .other, stock.unit == unit {
                    covered = stockQuantity
                }
            }
            return GroceryLine(
                key: key, name: bucket.name, quantity: quantity, unit: unit, aisle: Aisle.classify(bucket.name),
                sources: bucket.sources, pantryQuantity: covered, inPantry: stock != nil, isStaple: staples.contains(nameKey)
            )
        }
    }

    /// "cherry tomato" is covered by a pantry "tomato", and vice versa.
    static func pantryMatch(_ key: String, in pantry: [String: PantryStock]) -> PantryStock? {
        if let exact = pantry[key] { return exact }
        return pantry.first { pantryKey, _ in
            !pantryKey.isEmpty && (key.hasSuffix(" " + pantryKey) || pantryKey.hasSuffix(" " + key))
        }?.value
    }

    static func displayName(_ name: String) -> String {
        let base = name.split(separator: ",").first.map(String.init) ?? name
        let cleaned = base.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.capitalizedFirst
    }
}
