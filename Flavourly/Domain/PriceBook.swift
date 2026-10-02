import Foundation

/// What the cook actually paid for something: "₹60 for 1 kg onions", "$3.49 for 12 eggs".
struct PricePoint: Codable, Equatable {
    var key: String
    var name: String
    var price: Double
    var quantity: Double
    var unit: String
    var currency: String
    var date: Date
}

/// Recipe costs from the cook's own prices only — never guessed. Units are converted within a family
/// (g↔kg↔lb, ml↔l↔cup); counted things ("2 onions", "1 can") need a price for a count.
enum PriceBook {
    /// Share of priced ingredients needed before a cost is shown.
    static let minCoverage = 0.7

    /// Cost of `quantity unit` of a food at this price, or nil if the units can't be compared.
    static func cost(_ quantity: Double, unit: String, at point: PricePoint) -> Double? {
        guard quantity > 0, point.quantity > 0, point.price >= 0 else { return nil }
        let wanted = Units.canonical(unit) ?? unit
        let paid = Units.canonical(point.unit) ?? point.unit
        if let a = Units.toBase(quantity, unit: wanted), let b = Units.toBase(point.quantity, unit: paid),
           Units.family(wanted) == Units.family(paid) {
            return point.price * a / b
        }
        let countUnits: Set<String> = ["", "piece", "each"]
        if wanted == paid || (countUnits.contains(wanted) && countUnits.contains(paid)) {
            return point.price * quantity / point.quantity
        }
        return nil
    }

    struct Estimate: Equatable {
        let perServing: Double
        let coverage: Double
        let priced: Int
        let total: Int
    }

    /// Per-serving cost; nil until enough ingredients have a known price.
    /// Kitchen staples (salt, water, oil…) are left out of both the cost and the coverage.
    static func estimate(ingredients: [(name: String, quantity: Double?, unit: String)], servings: Int,
                         prices: [String: PricePoint], isStaple: (String) -> Bool) -> Estimate? {
        let lines = ingredients.filter { !isStaple($0.name) && ($0.quantity ?? 0) > 0 }
        guard !lines.isEmpty else { return nil }
        var total = 0.0
        var priced = 0
        for line in lines {
            guard let point = prices[FoodText.key(line.name)], let value = cost(line.quantity ?? 0, unit: line.unit, at: point) else { continue }
            total += value
            priced += 1
        }
        let coverage = Double(priced) / Double(lines.count)
        guard coverage >= minCoverage else { return nil }
        // Unpriced lines are filled at the average cost of the priced ones, so 70% coverage doesn't read as cheap.
        let scaled = total / Double(priced) * Double(lines.count)
        return Estimate(perServing: scaled / Double(max(1, servings)), coverage: coverage, priced: priced, total: lines.count)
    }

    /// Budget filter steps that make sense in the cook's currency (per serving).
    static func steps(currency: String) -> [Double] {
        switch currency {
        case "INR", "PKR", "LKR", "NPR", "BDT": return [50, 100, 200]
        case "JPY": return [300, 600, 1200]
        case "KRW": return [3000, 6000, 12000]
        case "IDR": return [15000, 30000, 60000]
        case "AED", "SAR", "QAR", "MYR", "BRL", "TRY", "PLN": return [10, 20, 40]
        case "ZAR", "MXN", "PHP", "THB", "EGP", "RUB", "UAH": return [40, 80, 160]
        default: return [2, 4, 8] // USD, EUR, GBP, CAD, AUD, SGD, CHF…
        }
    }
}
