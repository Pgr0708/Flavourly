import Foundation

// MARK: - Vocabulary

enum Allergen: String, CaseIterable, Codable, Hashable, Identifiable {
    case peanuts, treeNuts, milk, eggs, wheat, gluten, soy, fish, shellfish, sesame, mustard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .peanuts: "Peanuts"
        case .treeNuts: "Tree nuts"
        case .milk: "Milk"
        case .eggs: "Eggs"
        case .wheat: "Wheat"
        case .gluten: "Gluten"
        case .soy: "Soy"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        case .sesame: "Sesame"
        case .mustard: "Mustard"
        }
    }

    /// Accepts quiz / UI labels such as "Tree nuts" or raw values.
    init?(label: String) {
        let key = label.lowercased().replacingOccurrences(of: " ", with: "")
        guard let match = Allergen.allCases.first(where: { $0.rawValue.lowercased() == key || $0.label.lowercased().replacingOccurrences(of: " ", with: "") == key })
        else { return nil }
        self = match
    }
}

enum Diet: String, CaseIterable, Codable, Hashable, Identifiable {
    case vegetarian, eggetarian, vegan, pescatarian, jain, noOnionGarlic, halal, glutenFree, dairyFree, keto, lowCarb

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .eggetarian: "Eggetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        case .jain: "Jain"
        case .noOnionGarlic: "No onion / garlic"
        case .halal: "Halal"
        case .glutenFree: "Gluten free"
        case .dairyFree: "Dairy free"
        case .keto: "Keto"
        case .lowCarb: "Low carb"
        }
    }

    init?(label: String) {
        let key = label.lowercased().filter(\.isLetter)
        guard let match = Diet.allCases.first(where: { $0.label.lowercased().filter(\.isLetter) == key || $0.rawValue.lowercased() == key })
        else { return nil }
        self = match
    }
}

// MARK: - Results

struct FoodIssue: Hashable, Identifiable {
    enum Kind: String { case allergen, diet, dislike, spice }
    enum Severity: Int, Comparable {
        case check = 1, blocked = 2
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var id: String { "\(kind.rawValue)|\(ingredient)|\(reason)" }
    let ingredient: String
    let kind: Kind
    let severity: Severity
    let reason: String
}

struct FoodCheckResult: Equatable {
    var issues: [FoodIssue] = []
    /// Every allergen found in the ingredients, whether or not anyone is allergic (for "Contains …").
    var contains: Set<Allergen> = []

    var isBlocked: Bool { issues.contains { $0.severity == .blocked } }
    var needsCheck: Bool { issues.contains { $0.severity == .check } }
    var hasDislike: Bool { issues.contains { $0.kind == .dislike } }
    var isClear: Bool { issues.isEmpty }
    var allergenIssues: [FoodIssue] { issues.filter { $0.kind == .allergen } }
}

/// Everything that must hold for the people eating a meal.
struct FoodProfile: Equatable {
    var allergens: [Allergen: [String]] = [:]
    var customAllergens: [String: [String]] = [:]
    var diets: [Diet: [String]] = [:]
    var dislikes: [String: [String]] = [:]
    var mildOnly: [String] = []

    var isEmpty: Bool {
        allergens.isEmpty && customAllergens.isEmpty && diets.isEmpty && dislikes.isEmpty && mildOnly.isEmpty
    }

    var allergenSummary: String {
        let names = allergens.keys.sorted { $0.rawValue < $1.rawValue }.map { $0.label.lowercased() }
            + customAllergens.keys.sorted()
        return names.joined(separator: ", ")
    }

    mutating func add(person: String, allergies: [String], diets dietLabels: [String], dislikes items: [String], mild: Bool) {
        for label in allergies {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.lowercased() != "none known", trimmed.lowercased() != "other" else { continue }
            if let allergen = Allergen(label: trimmed) {
                allergens[allergen, default: []].append(person)
                // A wheat allergy is not coeliac disease, but gluten-free still means wheat-free.
            } else {
                customAllergens[trimmed.lowercased(), default: []].append(person)
            }
        }
        for label in dietLabels {
            guard let diet = Diet(label: label) else { continue }
            diets[diet, default: []].append(person)
            if diet == .glutenFree {
                allergens[.gluten, default: []].append(person)
                allergens[.wheat, default: []].append(person)
            }
            if diet == .dairyFree { allergens[.milk, default: []].append(person) }
        }
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty { dislikes[trimmed, default: []].append(person) }
        }
        if mild { mildOnly.append(person) }
        dedupe()
    }

    private mutating func dedupe() {
        allergens = allergens.mapValues { Array(Set($0)).sorted() }
        customAllergens = customAllergens.mapValues { Array(Set($0)).sorted() }
        diets = diets.mapValues { Array(Set($0)).sorted() }
        dislikes = dislikes.mapValues { Array(Set($0)).sorted() }
        mildOnly = Array(Set(mildOnly)).sorted()
    }
}

// MARK: - Text normalisation

enum FoodText {
    /// Lower-cased, accent-free, punctuation → spaces, light plural stemming, padded with spaces
    /// so " term " matches whole words and multi-word phrases alike.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        var tokens: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(stem(current))
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(stem(current)) }
        return " " + tokens.joined(separator: " ") + " "
    }

    static func stem(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("sses") || word.hasSuffix("xes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ss") || word.hasSuffix("us") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// Stable key for merging ingredients ("Cherry Tomatoes, halved" → "cherry tomato").
    static func key(_ name: String) -> String {
        let base = name.split(separator: ",").first.map(String.init) ?? name
        let noParens = base.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        let words = normalize(noParens).split(separator: " ").map(String.init).filter { !prepWords.contains($0) }
        return words.joined(separator: " ")
    }

    static let prepWords: Set<String> = [
        "fresh", "freshly", "chopped", "finely", "roughly", "minced", "diced", "sliced", "thinly", "grated", "crushed",
        "peeled", "large", "small", "medium", "ripe", "boneless", "skinless", "cooked", "raw", "halved", "quartered",
        "cubed", "shredded", "packed", "heaped", "level", "softened", "melted", "beaten", "room", "temperature",
        "optional", "organic", "about", "approx", "approximately", "to", "taste", "for", "garnish", "serving", "divided",
        "plus", "extra", "more", "needed", "a", "an", "of", "the", "and", "or", "juiced", "zested", "trimmed", "rinsed",
        "drained", "washed", "deseeded", "seeded", "pitted", "whole", "good", "quality", "handful", "pinch"
    ]
}

// MARK: - Rules

enum FoodRules {
    struct Term {
        let text: String
        let certain: Bool
    }

    struct Group {
        let terms: [Term]
        let exclusions: [String]
        /// "gluten free …", "dairy free …": neutralise the qualifier and the word after it.
        let negators: [String]
    }

    private static func group(_ certain: [String], likely: [String] = [], exclude: [String] = [], negators: [String] = []) -> Group {
        Group(
            terms: certain.map { Term(text: FoodText.normalize($0), certain: true) }
                + likely.map { Term(text: FoodText.normalize($0), certain: false) },
            exclusions: exclude.map(FoodText.normalize).sorted { $0.count > $1.count },
            negators: negators.map(FoodText.normalize)
        )
    }

    private static let glutenNegators = ["gluten free", "wheat free", "gf", "certified gluten free"]

    // Wheat vocabulary is reused for gluten.
    private static let wheatCertain = [
        "wheat", "flour", "plain flour", "all purpose flour", "self raising flour", "bread flour", "maida", "atta",
        "semolina", "sooji", "suji", "rava", "couscous", "bulgur", "bulghur", "cracked wheat", "dalia", "seitan",
        "spelt", "farro", "durum", "kamut", "einkorn", "freekeh", "breadcrumb", "breadcrumbs", "panko", "crouton", "croutons",
        "bread", "roti", "chapati", "chapatti", "phulka", "naan", "paratha", "puri", "poori", "bhatura", "kulcha", "pav",
        "bun", "buns", "pita", "bagel", "croissant", "tortilla", "pasta", "spaghetti", "penne", "fettuccine", "fettucine",
        "farfalle", "linguine", "macaroni", "lasagna", "lasagne", "fusilli", "rigatoni", "orzo", "ravioli", "tortellini",
        "pappardelle", "tagliatelle", "ramen", "udon", "lo mein", "hakka noodle", "pastry", "puff pastry", "filo", "phyllo",
        "pie crust", "pizza dough", "pizza base", "cracker", "crackers", "biscuit", "biscuits", "cookie", "cookies", "muffin", "waffle",
        "soy sauce", "shoyu", "wheat germ", "graham cracker", "matzo", "wafer", "rusk", "samosa", "wonton wrapper",
        "dumpling wrapper", "brioche", "challah"
    ]
    private static let wheatLikely = [
        "noodle", "noodles", "vermicelli", "soba", "gnocchi", "cake", "wrap", "teriyaki", "hoisin", "batter", "toast", "pancake mix"
    ]
    private static let wheatExclusions = [
        "buckwheat flour", "buckwheat noodle", "buckwheat noodles", "buckwheat", "rice flour", "almond flour", "coconut flour", "chickpea flour", "gram flour", "besan", "corn flour",
        "cornflour", "maize flour", "masa harina", "tapioca flour", "potato flour", "oat flour", "sorghum flour",
        "millet flour", "jowar flour", "bajra flour", "ragi flour", "quinoa flour", "arrowroot flour", "rice noodle",
        "rice noodles", "glass noodle", "glass noodles", "cellophane noodle", "rice vermicelli", "rice pasta", "gluten free",
        "wheat free", "corn tortilla", "rice paper", "gluten free bread", "gluten free pasta", "chickpea pasta",
        "lentil pasta", "zucchini noodle", "zucchini noodles", "kelp noodle", "shirataki", "lettuce wrap", "sweetbread",
        "cauliflower rice", "rice cake", "rice cakes", "wheatgrass"
    ]

    static let allergenGroups: [Allergen: Group] = [
        .peanuts: group(
            ["peanut", "peanuts", "groundnut", "groundnuts", "monkey nut", "arachis", "peanut butter", "peanut oil", "moongphali", "mungfali"],
            likely: ["satay", "nut", "nuts", "mixed nuts"],
            exclude: ["pine nut", "pine nuts", "brazil nut", "brazil nuts", "nut free", "tiger nut", "coconut"],
            negators: ["nut free", "peanut free"]
        ),
        .treeNuts: group(
            ["almond", "almonds", "cashew", "cashews", "walnut", "walnuts", "pecan", "pecans", "pistachio", "pistachios",
             "hazelnut", "hazelnuts", "macadamia", "brazil nut", "brazil nuts", "pine nut", "pine nuts", "pignoli", "chestnut",
             "chestnuts", "praline", "marzipan", "frangipane", "nutella", "gianduja", "badam", "kaju", "akhrot", "pista",
             "chironji", "cashew cream", "almond milk", "almond butter", "cashew butter"],
            likely: ["pesto", "nougat", "nut", "nuts", "mixed nuts", "nut butter", "baklava", "korma", "nut milk"],
            exclude: ["water chestnut", "water chestnuts", "nut free", "butternut", "coconut", "tiger nut", "peanut", "peanuts", "nutmeg"],
            negators: ["nut free", "tree nut free"]
        ),
        .milk: group(
            ["milk", "cream", "butter", "cheese", "yoghurt", "yogurt", "curd", "dahi", "ghee", "paneer", "khoa", "khoya", "mawa",
             "malai", "whey", "casein", "lactose", "buttermilk", "chaas", "lassi", "kefir", "ricotta", "mozzarella", "parmesan",
             "parmigiano", "cheddar", "feta", "halloumi", "mascarpone", "burrata", "brie", "gouda", "gruyere", "pecorino",
             "creme fraiche", "sour cream", "ice cream", "custard", "condensed milk", "evaporated milk", "milk powder", "kulfi",
             "rabri", "shrikhand", "quark", "cottage cheese", "cream cheese", "labneh", "skyr", "clotted cream",
             "half and half", "bechamel", "alfredo", "tzatziki", "raita", "queso", "milk chocolate", "brioche"],
            likely: ["naan"],
            exclude: ["coconut milk", "almond milk", "oat milk", "soy milk", "soya milk", "rice milk", "cashew milk", "hemp milk",
                      "pea milk", "plant milk", "nut milk", "coconut cream", "coconut yoghurt", "coconut yogurt", "soy yoghurt",
                      "soy yogurt", "vegan cheese", "vegan butter", "dairy free", "peanut butter", "almond butter",
                      "cashew butter", "nut butter", "seed butter", "sunflower butter", "cocoa butter", "shea butter",
                      "apple butter", "butter bean", "butter beans", "butter lettuce", "butternut", "cream of tartar",
                      "creamed coconut", "coconut butter", "cashew cream", "vegan cream", "oat cream", "soy cream"],
            negators: ["dairy free", "non dairy", "vegan", "plant based"]
        ),
        .eggs: group(
            ["egg", "eggs", "egg yolk", "egg white", "mayonnaise", "mayo", "aioli", "meringue", "custard", "hollandaise",
             "bearnaise", "eggnog", "brioche", "challah", "frittata", "omelette", "omelet", "quiche", "egg noodle", "egg noodles", "albumen"],
            exclude: ["egg free", "eggless", "vegan mayo", "vegan mayonnaise", "flax egg", "chia egg", "egg replacer", "aquafaba"],
            negators: ["egg free", "eggless", "vegan"]
        ),
        .wheat: group(wheatCertain, likely: wheatLikely, exclude: wheatExclusions, negators: glutenNegators),
        .gluten: group(
            wheatCertain + ["barley", "rye", "malt", "malt vinegar", "malted", "brewers yeast", "beer", "ale", "lager", "triticale"],
            likely: wheatLikely + ["oat", "oats", "oatmeal", "porridge oats", "granola", "muesli", "oat milk", "oat flour"],
            exclude: wheatExclusions.filter { $0 != "oat flour" } + ["gluten free oat", "gluten free oats", "certified gluten free", "ginger ale"],
            negators: glutenNegators
        ),
        .soy: group(
            ["soy", "soya", "soybean", "soybeans", "tofu", "tempeh", "edamame", "miso", "soy sauce", "tamari", "shoyu", "bean curd",
             "yuba", "natto", "textured vegetable protein", "tvp", "soy lecithin", "soy milk", "soya chunks", "nutrela"],
            likely: ["teriyaki", "hoisin", "vegetable protein"],
            exclude: ["soy free"],
            negators: ["soy free"]
        ),
        .fish: group(
            ["fish", "salmon", "tuna", "cod", "haddock", "hake", "pollock", "anchovy", "anchovies", "sardine", "sardines", "mackerel",
             "herring", "tilapia", "trout", "halibut", "snapper", "sea bass", "bass", "catfish", "carp", "pomfret", "rohu", "hilsa",
             "surmai", "kingfish", "bangda", "basa", "swordfish", "mahi mahi", "plaice", "monkfish", "fish sauce", "nam pla",
             "fish stock", "bonito", "dashi", "katsuobushi", "caviar", "roe", "bottarga", "surimi"],
            likely: ["worcestershire", "worcestershire sauce", "caesar dressing", "xo sauce"],
            exclude: ["fish free", "vegan fish sauce"],
            negators: ["vegan", "fish free"]
        ),
        .shellfish: group(
            ["shellfish", "shrimp", "shrimps", "prawn", "prawns", "crab", "lobster", "crayfish", "crawfish", "langoustine", "scampi",
             "krill", "scallop", "scallops", "mussel", "mussels", "clam", "clams", "oyster", "oysters", "cockle", "cockles", "whelk",
             "abalone", "squid", "calamari", "octopus", "cuttlefish", "oyster sauce", "shrimp paste", "dried shrimp", "prawn cracker",
             "sea urchin"],
            exclude: ["oyster mushroom", "oyster mushrooms", "king oyster", "crab apple", "crab apples", "vegan oyster sauce", "mushroom oyster sauce"],
            negators: ["vegan", "shellfish free"]
        ),
        .sesame: group(
            ["sesame", "sesame oil", "sesame seed", "sesame seeds", "tahini", "tahina", "til", "gingelly", "benne", "gomasio"],
            likely: ["hummus", "halva", "furikake", "za atar", "zaatar", "dukkah"]
        ),
        .mustard: group(["mustard", "mustard seed", "mustard seeds", "mustard oil", "dijon", "rai", "sarson"])
    ]

    private static let meatTerms = [
        "chicken", "beef", "pork", "lamb", "mutton", "goat", "veal", "venison", "bacon", "ham", "sausage", "sausages", "salami",
        "pepperoni", "prosciutto", "chorizo", "pancetta", "guanciale", "turkey", "duck", "goose", "quail", "rabbit", "keema",
        "kheema", "steak", "ribs", "brisket", "ground beef", "meatball", "meatballs", "meat", "gelatin", "gelatine", "lard",
        "suet", "tallow", "bone broth", "chicken stock", "chicken broth", "beef stock", "beef broth", "liver", "oxtail", "boti"
    ]
    private static let meatExclusions = [
        "kidney bean", "kidney beans", "vegan", "plant based", "meatless", "vegetarian sausage", "veggie sausage",
        "veg sausage", "soya chunks", "vegetable stock", "vegetable broth", "chicken of the woods", "mock meat", "jackfruit",
        "coconut meat", "crab apple", "goat cheese", "goats cheese", "goat milk", "goats milk", "beef tomato",
        "beefsteak tomato", "lambs lettuce", "cauliflower steak", "mushroom steak"
    ]
    private static let seafoodTerms: [String] = allergenGroups[.fish]!.terms.filter(\.certain).map(\.text)
        + allergenGroups[.shellfish]!.terms.map(\.text)
    private static let honeyTerms = ["honey"]
    private static let rootTerms = [
        "onion", "onions", "garlic", "potato", "potatoes", "carrot", "carrots", "beetroot", "beet", "beets", "radish", "radishes",
        "turnip", "turnips", "ginger", "sweet potato", "yam", "shallot", "shallots", "leek", "leeks", "spring onion",
        "spring onions", "scallion", "scallions", "mushroom", "mushrooms", "arbi", "taro", "cassava", "mooli", "adrak",
        "lehsun", "lahsun", "pyaz", "pyaaz", "aloo", "gajar"
    ]
    private static let haramTerms = [
        "pork", "bacon", "ham", "prosciutto", "pancetta", "guanciale", "lard", "chorizo", "salami", "pepperoni", "gelatin",
        "gelatine", "wine", "beer", "rum", "brandy", "sake", "mirin", "vodka", "whisky", "whiskey", "bourbon", "sherry",
        "cognac", "liqueur", "tequila", "gin", "cider", "kirsch"
    ]
    private static let halalExclusions = [
        "wine vinegar", "red wine vinegar", "white wine vinegar", "root beer", "ginger beer", "turkey ham", "chicken ham",
        "beef bacon", "turkey bacon", "beef salami", "chicken salami", "beef pepperoni", "halal gelatin", "agar", "ginger", "cider vinegar"
    ]
    private static let alliumTerms = [
        "onion", "onions", "garlic", "shallot", "shallots", "leek", "leeks", "spring onion", "spring onions", "scallion",
        "scallions", "chive", "chives", "garlic powder", "onion powder", "garlic paste", "pyaz", "pyaaz", "lehsun", "lahsun"
    ]
    static let spicyTerms = [
        "chilli", "chillies", "chili", "chilies", "chile", "chiles", "cayenne", "jalapeno", "jalapenos", "habanero", "serrano",
        "scotch bonnet", "birds eye", "hot sauce", "sriracha", "harissa", "gochujang", "sambal", "chilli flakes",
        "red pepper flakes", "chilli powder", "chili powder", "chipotle", "peri peri", "piri piri", "tabasco", "green chilli",
        "mirchi", "vindaloo"
    ]

    private static let normalizedSpicy = spicyTerms.map(FoodText.normalize)

    // MARK: Matching

    private static var allergenCache: [String: [(Allergen, String, Bool)]] = [:]

    /// Allergens present in one ingredient line (term found, and whether it's certain or only likely).
    static func allergens(in ingredient: String) -> [(allergen: Allergen, term: String, certain: Bool)] {
        let text = FoodText.normalize(ingredient)
        if let cached = allergenCache[text] { return cached.map { ($0.0, $0.1, $0.2) } }
        var found: [(Allergen, String, Bool)] = []
        for allergen in Allergen.allCases {
            guard let group = allergenGroups[allergen] else { continue }
            if let hit = firstMatch(in: text, group: group) {
                found.append((allergen, hit.text.trimmingCharacters(in: .whitespaces), hit.certain))
            }
        }
        if allergenCache.count > 4000 { allergenCache.removeAll() }
        allergenCache[text] = found
        return found.map { ($0.0, $0.1, $0.2) }
    }

    /// Why an ingredient breaks a diet, or nil when it fits.
    static func dietViolation(_ ingredient: String, diet: Diet) -> (term: String, certain: Bool)? {
        let text = FoodText.normalize(ingredient)
        func hit(_ terms: [String], exclude: [String] = []) -> String? {
            let cleaned = clean(text, exclusions: exclude.map(FoodText.normalize))
            return terms.map(FoodText.normalize).first { cleaned.contains($0) }?.trimmingCharacters(in: .whitespaces)
        }
        func allergenHit(_ allergen: Allergen) -> (String, Bool)? {
            guard let group = allergenGroups[allergen], let match = firstMatch(in: text, group: group) else { return nil }
            return (match.text.trimmingCharacters(in: .whitespaces), match.certain)
        }
        switch diet {
        case .vegetarian, .eggetarian, .pescatarian, .vegan, .jain:
            if let meat = hit(meatTerms, exclude: meatExclusions) { return (meat, true) }
            if diet != .pescatarian, let seafood = hit(seafoodTerms, exclude: allergenGroups[.shellfish]!.exclusions + allergenGroups[.fish]!.exclusions) {
                return (seafood, true)
            }
            if diet == .vegetarian || diet == .pescatarian || diet == .eggetarian { return nil }
            if let egg = allergenHit(.eggs) { return egg }
            if diet == .vegan, let dairy = allergenHit(.milk) { return dairy }
            if let honey = hit(honeyTerms) { return (honey, true) }
            if diet == .jain, let root = hit(rootTerms, exclude: ["ginger ale", "spring onion greens"]) { return (root, true) }
            return nil
        case .noOnionGarlic:
            return hit(alliumTerms).map { ($0, true) }
        case .halal:
            return hit(haramTerms, exclude: halalExclusions).map { ($0, true) }
        case .glutenFree:
            return allergenHit(.gluten)
        case .dairyFree:
            return allergenHit(.milk)
        case .keto, .lowCarb:
            return nil // judged on carbs per serving, not ingredients
        }
    }

    private static let highCarbTerms = [
        "pasta", "spaghetti", "penne", "noodle", "noodles", "rice", "bread", "naan", "roti", "chapati", "paratha", "tortilla",
        "potato", "potatoes", "sugar", "flour", "maida", "atta", "oats", "couscous", "polenta", "cornmeal", "honey", "jaggery",
        "banana", "bun", "bagel", "semolina", "rava", "poha", "sweet potato", "corn"
    ].map(FoodText.normalize)
    private static let lowCarbExclusions = ["cauliflower rice", "almond flour", "coconut flour", "shirataki", "zucchini noodles", "sugar free", "sugar-free", "rice vinegar"]
        .map(FoodText.normalize)

    static func isHighCarb(_ ingredient: String) -> Bool {
        let cleaned = clean(FoodText.normalize(ingredient), exclusions: lowCarbExclusions)
        return highCarbTerms.contains { cleaned.contains($0) }
    }

    static func isSpicy(_ ingredient: String) -> Bool {
        let text = FoodText.normalize(ingredient)
        let cleaned = clean(text, exclusions: [FoodText.normalize("sweet paprika")])
        return normalizedSpicy.contains { cleaned.contains($0) }
    }

    // MARK: Check

    /// Deterministic safety + preference check. AI output is always passed through this.
    static func check(ingredients: [String], profile: FoodProfile, carbsPerServing: Double? = nil) -> FoodCheckResult {
        var result = FoodCheckResult()
        var seen = Set<String>()
        func add(_ issue: FoodIssue) {
            if seen.insert(issue.id).inserted { result.issues.append(issue) }
        }

        for raw in ingredients {
            let ingredient = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ingredient.isEmpty else { continue }
            let normalized = FoodText.normalize(ingredient)

            for match in allergens(in: ingredient) {
                result.contains.insert(match.allergen)
                guard let people = profile.allergens[match.allergen] else { continue }
                let severity: FoodIssue.Severity = match.certain ? .blocked : .check
                let why = match.certain ? "" : " (likely)"
                add(FoodIssue(
                    ingredient: ingredient, kind: .allergen, severity: severity,
                    reason: "\(match.term.capitalizedFirst)\(why) — \(possessive(people)) \(match.allergen.label.lowercased()) allergy"
                ))
            }
            for (keyword, people) in profile.customAllergens where normalized.contains(FoodText.normalize(keyword)) {
                add(FoodIssue(ingredient: ingredient, kind: .allergen, severity: .blocked,
                              reason: "\(keyword.capitalizedFirst) — \(possessive(people)) allergy"))
            }
            for (diet, people) in profile.diets {
                guard let violation = dietViolation(ingredient, diet: diet) else { continue }
                add(FoodIssue(
                    ingredient: ingredient, kind: .diet, severity: violation.certain ? .blocked : .check,
                    reason: "\(violation.term.capitalizedFirst) — not \(diet.label.lowercased()) (\(names(people)))"
                ))
            }
            for (item, people) in profile.dislikes where normalized.contains(FoodText.normalize(item)) {
                add(FoodIssue(ingredient: ingredient, kind: .dislike, severity: .check,
                              reason: "\(item.capitalizedFirst) — \(names(people)) would rather skip it"))
            }
            if !profile.mildOnly.isEmpty, isSpicy(ingredient) {
                add(FoodIssue(ingredient: ingredient, kind: .spice, severity: .check,
                              reason: "Spicy — keep it mild for \(names(profile.mildOnly))"))
            }
        }

        if let carbs = carbsPerServing, carbs > 0 {
            if let people = profile.diets[.keto], carbs > 20 {
                add(FoodIssue(ingredient: "Carbs", kind: .diet, severity: .check,
                              reason: "\(Int(carbs)) g carbs a serving — high for keto (\(names(people)))"))
            } else if let people = profile.diets[.lowCarb], carbs > 35 {
                add(FoodIssue(ingredient: "Carbs", kind: .diet, severity: .check,
                              reason: "\(Int(carbs)) g carbs a serving — high for low carb (\(names(people)))"))
            }
        }
        // No nutrition to judge carbs by: still warn keto / low-carb eaters about obvious starches.
        if (carbsPerServing ?? 0) == 0, let people = profile.diets[.keto] ?? profile.diets[.lowCarb],
           let starch = ingredients.first(where: isHighCarb) {
            let diet = profile.diets[.keto] != nil ? "keto" : "low carb"
            add(FoodIssue(ingredient: starch, kind: .diet, severity: .check,
                          reason: "\(starch.capitalizedFirst) — probably high in carbs for \(diet) (\(names(people)))"))
        }
        result.issues.sort { ($0.severity, $0.ingredient) > ($1.severity, $1.ingredient) }
        return result
    }

    // MARK: Helpers

    private static func firstMatch(in text: String, group: Group) -> Term? {
        let cleaned = clean(negate(text, group.negators), exclusions: group.exclusions)
        return group.terms.first { cleaned.contains($0.text) }
    }

    /// Drops everything from a "free-from" qualifier onwards: "gluten free all purpose flour" is safe,
    /// but "flour (gluten free if you like)" still counts as wheat.
    private static func negate(_ text: String, _ negators: [String]) -> String {
        var result = text
        for negator in negators {
            if let range = result.range(of: negator) { result = String(result[..<range.lowerBound]) + " " }
        }
        return result
    }

    private static func clean(_ text: String, exclusions: [String]) -> String {
        var cleaned = text
        for phrase in exclusions where cleaned.contains(phrase) {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ")
        }
        return cleaned
    }

    static func names(_ people: [String]) -> String {
        switch people.count {
        case 0: "someone"
        case 1: people[0]
        case 2: "\(people[0]) & \(people[1])"
        default: people.dropLast().joined(separator: ", ") + " & " + people.last!
        }
    }

    static func possessive(_ people: [String]) -> String {
        let joined = names(people)
        if people == ["You"] { return "your" }
        return joined.hasSuffix("s") ? joined + "'" : joined + "'s"
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
