import Foundation

// Run: swiftc Flavourly/Domain/*.swift Flavourly/Data/RecipeDraft.swift Tests/DomainCheck.swift -o /tmp/domaincheck && /tmp/domaincheck
@main
struct DomainCheck {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition {
            failures += 1
            print("✘ line \(line): \(message)")
        }
    }

    static func allergens(_ text: String) -> Set<Allergen> { Set(FoodRules.allergens(in: text).map(\.allergen)) }
    static func certain(_ text: String, _ allergen: Allergen) -> Bool? {
        FoodRules.allergens(in: text).first { $0.allergen == allergen }?.certain
    }

    static func main() {
        // Allergens — the traps competitor reviews complain about.
        check(!allergens("400 ml coconut milk").contains(.milk), "coconut milk is not dairy")
        check(certain("200 ml heavy cream", .milk) == true, "cream is dairy")
        check(allergens("2 tbsp peanut butter") == [.peanuts], "peanut butter is peanut only: \(allergens("2 tbsp peanut butter"))")
        check(allergens("2 tbsp soy sauce").isSuperset(of: [.wheat, .gluten, .soy]), "soy sauce has wheat, gluten, soy")
        check(allergens("100 g buckwheat flour").isDisjoint(with: [.wheat, .gluten]), "buckwheat is gluten free")
        check(allergens("50 g almond flour") == [.treeNuts], "almond flour: tree nuts only, got \(allergens("50 g almond flour"))")
        check(allergens("1/4 tsp nutmeg").isEmpty, "nutmeg is not a nut")
        check(allergens("1 butternut squash").isEmpty, "butternut squash is not a nut")
        check(allergens("1 eggplant").isEmpty, "eggplant is not egg")
        check(certain("3 tbsp basil pesto", .treeNuts) == false, "pesto is a likely tree nut")
        check(certain("1 cup rolled oats", .gluten) == false && !allergens("1 cup rolled oats").contains(.wheat), "oats: gluten check, not wheat")
        check(allergens("200 g oyster mushrooms").isEmpty, "oyster mushroom is not shellfish")
        check(allergens("200 g rice noodles").isEmpty, "rice noodles are wheat free")
        check(allergens("250 g paneer") == [.milk] && allergens("2 tbsp ghee") == [.milk], "paneer & ghee are dairy")
        check(allergens("1 can water chestnuts").isEmpty, "water chestnut is not a tree nut")
        check(allergens("4 cloves garlic").isEmpty, "garlic is safe")
        check(allergens("250 g spaghetti").isSuperset(of: [.wheat, .gluten]), "spaghetti has wheat")
        check(allergens("2 large eggs").contains(.eggs), "eggs")
        check(allergens("200 g gluten-free all-purpose flour").isDisjoint(with: [.wheat, .gluten]), "GF flour is safe")
        check(allergens("2 tbsp vegan cream cheese").isEmpty, "vegan cream cheese is dairy free")
        check(allergens("1 cup flour (gluten free if you like)").contains(.wheat), "default flour is still wheat")
        check(allergens("2 kiwis").isEmpty && FoodText.normalize("2 kiwis") == " 2 kiwi ", "kiwis stem to kiwi")

        // Diets
        check(FoodRules.dietViolation("500 ml chicken stock", diet: .vegetarian) != nil, "chicken stock is not vegetarian")
        check(FoodRules.dietViolation("500 ml vegetable stock", diet: .vegetarian) == nil, "veg stock is vegetarian")
        check(FoodRules.dietViolation("100 g goat cheese", diet: .vegetarian) == nil, "goat cheese is vegetarian")
        check(FoodRules.dietViolation("1 can kidney beans", diet: .vegan) == nil, "kidney beans are vegan")
        check(FoodRules.dietViolation("1 onion", diet: .jain) != nil, "onion is not Jain")
        check(FoodRules.dietViolation("2 tomatoes", diet: .jain) == nil, "tomato is Jain")
        check(FoodRules.dietViolation("1 tbsp honey", diet: .vegan) != nil, "honey is not vegan")
        check(FoodRules.dietViolation("2 eggs", diet: .eggetarian) == nil, "eggetarian eats eggs")
        check(FoodRules.dietViolation("2 eggs", diet: .jain) != nil, "Jain excludes eggs")
        check(FoodRules.dietViolation("2 tbsp peanut butter", diet: .vegan) == nil, "peanut butter is vegan")
        check(FoodRules.dietViolation("200 g salmon", diet: .pescatarian) == nil, "pescatarians eat fish")
        check(FoodRules.dietViolation("200 g chicken", diet: .pescatarian) != nil, "pescatarians skip chicken")
        check(FoodRules.dietViolation("2 cloves garlic", diet: .noOnionGarlic) != nil, "garlic breaks no-onion-garlic")

        // Full check with a household profile
        var profile = FoodProfile()
        profile.add(person: "Priya", allergies: ["Tree nuts", "Peanuts"], diets: [], dislikes: ["mushrooms"], mild: false)
        profile.add(person: "Anaya", allergies: [], diets: [], dislikes: [], mild: true)
        let pesto = FoodRules.check(ingredients: ["3 tbsp basil pesto", "250 g farfalle"], profile: profile)
        check(pesto.needsCheck && !pesto.isBlocked, "pesto needs a check, not a block")
        check(FoodRules.check(ingredients: ["200 ml cashew cream"], profile: profile).isBlocked, "cashew is blocked")
        check(FoodRules.check(ingredients: ["150 g button mushrooms"], profile: profile).hasDislike, "dislike found")
        let spicy = FoodRules.check(ingredients: ["1 tsp chilli flakes"], profile: profile)
        check(spicy.issues.contains { $0.kind == .spice }, "spice flagged for mild eater")
        check(!FoodRules.check(ingredients: ["1 tsp sweet paprika"], profile: profile).issues.contains { $0.kind == .spice }, "sweet paprika is mild")
        var glutenFree = FoodProfile()
        glutenFree.add(person: "Rahul", allergies: [], diets: ["Gluten free"], dislikes: [], mild: false)
        check(FoodRules.check(ingredients: ["200 g spaghetti"], profile: glutenFree).isBlocked, "gluten free blocks spaghetti")
        check(!FoodRules.check(ingredients: ["200 g rice noodles"], profile: glutenFree).isBlocked, "rice noodles fine for GF")
        var custom = FoodProfile()
        custom.add(person: "Priya", allergies: ["Kiwi"], diets: [], dislikes: [], mild: false)
        check(FoodRules.check(ingredients: ["2 kiwis, sliced"], profile: custom).isBlocked, "custom allergy blocks")

        // Parser
        var p = IngredientParser.parse("2 tbsp olive oil")
        check(p.quantity == 2 && p.unit == "tbsp" && p.name == "olive oil", "olive oil: \(p)")
        p = IngredientParser.parse("1 1/2 cups flour")
        check(p.quantity == 1.5 && p.unit == "cup" && p.name == "flour", "mixed number: \(p)")
        p = IngredientParser.parse("½ tsp salt")
        check(p.quantity == 0.5 && p.unit == "tsp" && p.name == "salt", "unicode half: \(p)")
        p = IngredientParser.parse("200g paneer, cubed")
        check(p.quantity == 200 && p.unit == "g" && p.name == "paneer" && p.note == "cubed", "glued unit: \(p)")
        p = IngredientParser.parse("3-4 cloves garlic, minced")
        check(p.quantity == 3 && p.quantityMax == 4 && p.unit == "clove" && p.name == "garlic", "range: \(p)")
        p = IngredientParser.parse("Salt to taste")
        check(p.quantity == nil && p.isVague, "to taste is vague: \(p)")
        p = IngredientParser.parse("a little chilli flakes")
        check(p.isVague && p.confidence < 1, "a little is vague")
        p = IngredientParser.parse("1 (400 g) can chickpeas")
        check(p.quantity == 1 && p.unit == "can" && p.name == "chickpeas" && p.note == "400 g", "can with size: \(p)")
        p = IngredientParser.parse("a pinch of salt")
        check(p.quantity == 1 && p.unit == "pinch" && p.name == "salt", "a pinch: \(p)")
        p = IngredientParser.parse("1½ cups milk")
        check(p.quantity == 1.5 && p.unit == "cup", "glued unicode: \(p)")
        p = IngredientParser.parse("4 cloves garlic (optional)")
        check(p.isOptional && p.name == "garlic", "optional: \(p)")
        p = IngredientParser.parse("• 2 large eggs")
        check(p.quantity == 2 && p.name == "large eggs", "bullet + adjective: \(p)")

        // Amounts
        check(Amount.text(quantity: 320, unit: "g", system: .metric) == "320 g", "320 g")
        check(Amount.text(quantity: 1.5, unit: "cup", system: .metric) == "360 ml", "cups → ml: \(Amount.text(quantity: 1.5, unit: "cup", system: .metric))")
        check(Amount.text(quantity: 1.5, unit: "cup", system: .us) == "1 ½ cups", "cups stay: \(Amount.text(quantity: 1.5, unit: "cup", system: .us))")
        check(Amount.text(quantity: 2, unit: "tbsp", system: .metric, scale: 2) == "4 tbsp", "scaling")
        check(Amount.text(quantity: 3, max: 4, unit: "clove", system: .metric) == "3–4 cloves", "range text: \(Amount.text(quantity: 3, max: 4, unit: "clove", system: .metric))")
        check(Amount.text(quantity: 0.5, unit: "", system: .metric) == "½", "half an onion")
        check(Amount.text(quantity: 1200, unit: "g", system: .metric) == "1.2 kg", "kg: \(Amount.text(quantity: 1200, unit: "g", system: .metric))")
        check(Amount.text(quantity: 200, unit: "g", system: .us) == "7 oz", "g → oz: \(Amount.text(quantity: 200, unit: "g", system: .us))")

        // Grocery merge, "used by", pantry subtraction
        let inputs = [
            GroceryInput(recipeTitle: "Tomato Basil Penne", when: "Sat dinner", name: "tomatoes", quantity: 4, unit: ""),
            GroceryInput(recipeTitle: "Caprese Pasta Salad", when: "Fri lunch", name: "Tomatoes, halved", quantity: 2, unit: ""),
            GroceryInput(recipeTitle: "Creamy Garlic Pasta", when: "Mon dinner", name: "tomato", quantity: 2, unit: ""),
            GroceryInput(recipeTitle: "Quinoa Bowl", when: "Thu dinner", name: "avocado", quantity: 3, unit: ""),
            GroceryInput(recipeTitle: "Penne", when: "Sat dinner", name: "olive oil", quantity: 2, unit: "tbsp"),
            GroceryInput(recipeTitle: "Salad", when: "Fri lunch", name: "olive oil", quantity: 1, unit: "tsp"),
            GroceryInput(recipeTitle: "Bowl", when: "Thu dinner", name: "spinach", quantity: 200, unit: "g"),
            GroceryInput(recipeTitle: "Smoothie", when: "Sat breakfast", name: "spinach", quantity: 2, unit: "cup"),
            GroceryInput(recipeTitle: "Penne", when: "Sat dinner", name: "salt", quantity: nil, unit: ""),
            GroceryInput(recipeTitle: "Pasta", when: "Mon dinner", name: "garlic", quantity: 4, unit: "clove")
        ]
        let pantry = [PantryStock(name: "Avocado", quantity: 1, unit: ""), PantryStock(name: "garlic", quantity: nil, unit: "")]
        let lines = GroceryBuilder.build(inputs, pantry: pantry)
        let tomato = lines.first { $0.name.lowercased().hasPrefix("tomato") }
        check(tomato?.quantity == 8 && tomato?.sources.count == 3, "tomatoes merged to 8 from 3 recipes: \(String(describing: tomato))")
        let avocado = lines.first { $0.name == "Avocado" }
        check(avocado?.toBuy == 2 && avocado?.coveredByPantry == false, "avocado: have 1, buy 2")
        let oil = lines.first { $0.name == "Olive oil" }
        check(oil != nil && abs((oil?.quantity ?? 0) - 34.5) < 0.2 && oil?.unit == "ml", "spoons merge to ml: \(String(describing: oil))")
        check(lines.filter { $0.name == "Spinach" }.count == 2, "mass and volume spinach stay separate")
        check(lines.first { $0.name == "Salt" }?.isStaple == true, "salt is a staple")
        check(lines.first { $0.name == "Garlic" }?.coveredByPantry == true, "garlic covered by pantry")
        check(tomato?.aisle == .produce && oil?.aisle == .oils, "aisles")

        // Recommender
        let recipes = [
            RecipeFacts(id: "pesto", title: "Pesto Farfalle", ingredientNames: ["250 g farfalle", "3 tbsp basil pesto", "200 g cherry tomatoes"], minutes: 20, slots: [.lunch, .dinner]),
            RecipeFacts(id: "bowl", title: "Chicken Avocado Quinoa Bowl", ingredientNames: ["200 g chicken breast", "1 avocado", "100 g spinach", "100 g quinoa"], minutes: 20, slots: [.lunch, .dinner], protein: 38),
            RecipeFacts(id: "curry", title: "Slow Lamb Curry", ingredientNames: ["500 g lamb", "2 onions"], minutes: 120, slots: [.dinner]),
            RecipeFacts(id: "pancakes", title: "Berry Ricotta Pancakes", ingredientNames: ["2 eggs", "250 g ricotta", "100 g flour"], minutes: 20, slots: []),
            RecipeFacts(id: "penne", title: "Tomato Basil Penne", ingredientNames: ["300 g penne", "6 tomatoes", "basil"], minutes: 25, slots: [.dinner])
        ]
        var context = RankContext()
        context.profile = profile
        context.maxMinutes = 30
        context.slot = .dinner
        context.pantry = [PantrySignal(key: "spinach", name: "Spinach", daysLeft: 0), PantrySignal(key: "avocado", name: "Avocado", daysLeft: 3)]
        context.highProtein = true
        let ranked = Recommender.rank(recipes, context)
        check(ranked.first?.id == "bowl", "use-soon + protein bowl ranks first: \(ranked.map(\.id))")
        check(!ranked.contains { $0.id == "curry" }, "2-hour curry is over the time limit")
        check(!ranked.contains { $0.id == "pancakes" }, "pancakes are not dinner (inferred slot)")
        check(ranked.first?.reasons.contains { $0.contains("spinach") } == true, "reason mentions use-soon spinach: \(ranked.first?.reasons ?? [])")
        var veggie = context
        veggie.profile.add(person: "Priya", allergies: [], diets: ["Vegetarian"], dislikes: [], mild: false)
        check(!Recommender.rank(recipes, veggie).contains { $0.id == "bowl" }, "vegetarian drops the chicken bowl")
        var onlyHave = context
        onlyHave.maxMissing = 0
        check(Recommender.rank(recipes, onlyHave).isEmpty, "nothing fully in stock")
        var craving = context
        craving.craving = "something with pesto"
        check(Recommender.rank(recipes, craving).first?.id == "pesto", "craving lifts pesto: \(Recommender.rank(recipes, craving).map(\.id))")

        // Planner: fills only empty slots, dinner → next-day lunch leftovers, never repeats
        let calendar = Calendar(identifier: .gregorian)
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let friday = calendar.date(byAdding: .day, value: 1, to: thursday)!
        let saturday = calendar.date(byAdding: .day, value: 2, to: thursday)!
        var base = RankContext()
        base.profile = profile
        let picks = Planner.fill(
            empty: [PlanSlot(day: thursday, slot: .dinner), PlanSlot(day: friday, slot: .lunch), PlanSlot(day: friday, slot: .dinner)],
            existing: [PlanSlot(day: saturday, slot: .dinner): "pesto"],
            recipes: recipes, base: base, options: PlannerOptions(), calendar: calendar
        )
        check(picks.count == 3, "three slots filled: \(picks)")
        let thuDinner = picks.first { $0.slot == PlanSlot(day: thursday, slot: .dinner) }
        let friLunch = picks.first { $0.slot == PlanSlot(day: friday, slot: .lunch) }
        check(friLunch?.leftoverOf == thuDinner?.slot && friLunch?.recipeID == thuDinner?.recipeID, "Friday lunch is Thursday's leftovers")
        check(!picks.contains { $0.recipeID == "pesto" && $0.leftoverOf == nil }, "locked Saturday pesto is not repeated")

        validation()
        shoppingAmounts()
        ingredientArt()
        halal()

        if failures == 0 {
            print("DomainCheck passed")
        } else {
            print("DomainCheck: \(failures) failure(s)")
            exit(1)
        }
    }

    // MARK: - Sanitising & validation (what users type, paste or share)

    static func halal() {
        check(Diet(label: "Halal") == .halal, "Halal label parses")
        for line in ["200 g bacon", "1 tbsp mirin", "100 ml white wine", "2 tsp gelatine", "250 g pork mince"] {
            check(FoodRules.dietViolation(line, diet: .halal) != nil, "\(line) is not halal")
        }
        for line in ["500 g chicken", "1 tbsp red wine vinegar", "2 tbsp ginger, grated", "100 g turkey bacon", "1 can ginger beer"] {
            check(FoodRules.dietViolation(line, diet: .halal) == nil, "\(line) is halal")
        }
    }

    static func ingredientArt() {
        let cases: [(String, String)] = [("2 tbsp peanut butter", "🥜"), ("1 tbsp soy sauce", "🥢"), ("200 g rice noodles", "🍜"),
                                         ("400 ml coconut milk", "🥥"), ("1 cup almond milk", "🥛"), ("1 butternut squash", "🎃"),
                                         ("1 eggplant", "🍆"), ("2 tbsp butter", "🧈"), ("200 g cream cheese", "🧀"), ("2 tbsp cornflour", "🌾"),
                                         ("1 steak", "🥩"), ("mystery ingredient", "🥄")]
        for (line, emoji) in cases {
            check(IngredientArt.emoji(for: line) == emoji, "\(line) → \(emoji), got \(IngredientArt.emoji(for: line))")
        }
        check(IngredientArt.assetName(for: "2 eggs") == "IngEggs" && IngredientArt.assetName(for: "1 egg") == "IngEggs", "egg photo")
        check(IngredientArt.assetName(for: "1 eggplant") == nil, "eggplant is not eggs")
        check(IngredientArt.assetName(for: "3 tomatoes") == "IngTomato", "tomatoes photo")
        check(IngredientArt.assetName(for: "2 tbsp olive oil") == "IngOil", "olive oil photo")
    }

    static func shoppingAmounts() {
        // Metric spoons for small volumes, ml from 30 ml up.
        check(Amount.text(quantity: 3.7, unit: "ml", system: .metric) == "¾ tsp", "3.7 ml → ¾ tsp: \(Amount.text(quantity: 3.7, unit: "ml", system: .metric))")
        check(Amount.text(quantity: 10, unit: "ml", system: .metric) == "2 tsp", "10 ml → 2 tsp")
        check(Amount.text(quantity: 22.5, unit: "ml", system: .metric) == "1 ½ tbsp", "22.5 ml → 1 ½ tbsp: \(Amount.text(quantity: 22.5, unit: "ml", system: .metric))")
        check(Amount.text(quantity: 45, unit: "ml", system: .metric) == "45 ml", "45 ml stays ml")
        check(Amount.text(quantity: 1, unit: "tbsp", system: .metric, scale: 0.25) == "¾ tsp" || Amount.text(quantity: 1, unit: "tbsp", system: .metric, scale: 0.25) == "¼ tbsp",
              "scaled tbsp stays a spoon: \(Amount.text(quantity: 1, unit: "tbsp", system: .metric, scale: 0.25))")
        // The list never asks for half an egg, but doesn't round 2.02 up to 3.
        let half = GroceryBuilder.build([GroceryInput(recipeTitle: "Pancakes", when: "Thu breakfast", name: "eggs", quantity: 0.5, unit: "")], pantry: [])
        check(half.first?.quantity == 1, "½ egg → buy 1: \(String(describing: half.first?.quantity))")
        let nearly = GroceryBuilder.build([GroceryInput(recipeTitle: "A", when: "Mon dinner", name: "onion", quantity: 2.02, unit: "")], pantry: [])
        check(nearly.first?.quantity == 2, "2.02 onions → 2")
        let cloves = GroceryBuilder.build([GroceryInput(recipeTitle: "A", when: "Mon dinner", name: "garlic", quantity: 1.5, unit: "clove"),
                                           GroceryInput(recipeTitle: "B", when: "Tue dinner", name: "garlic", quantity: 2, unit: "clove")], pantry: [])
        check(cloves.first?.quantity == 4, "1.5 + 2 cloves → 4: \(String(describing: cloves.first?.quantity))")
        let pinch = GroceryBuilder.build([GroceryInput(recipeTitle: "A", when: "Mon dinner", name: "saffron", quantity: 0.5, unit: "pinch")], pantry: [])
        check(pinch.first?.quantity == 0.5, "pinches are not rounded")
        let covered = GroceryBuilder.build([GroceryInput(recipeTitle: "A", when: "Mon", name: "eggs", quantity: 0.5, unit: "")],
                                           pantry: [PantryStock(name: "eggs", quantity: 6, unit: "")])
        check(covered.first?.coveredByPantry == true, "6 eggs at home cover it")
    }

    static func validation() {
        // Sanitize.text
        check(Sanitize.text("  Hello\u{200B} <b>World</b>\t!  ") == "Hello World !", "tags, zero-width, tabs: \(Sanitize.text("  Hello\u{200B} <b>World</b>\t!  "))")
        check(Sanitize.text("a\u{0007}b") == "ab", "control characters removed")
        check(Sanitize.text("abc\u{202E}def") == "abcdef", "bidi override removed")
        check(Sanitize.text("line1\n\n\n\nline2  \n  line3", multiline: true) == "line1\n\nline2\nline3", "multiline collapse")
        check(Sanitize.text("a\nb") == "a b", "single-line flattens newlines")
        check(Sanitize.text("👩‍🍳 Chef") == "👩‍🍳 Chef", "emoji with ZWJ kept")
        check(Sanitize.text("पनीर टिक्का") == "पनीर टिक्का", "Hindi kept")
        check(Sanitize.text("cook < 5 min") == "cook < 5 min", "a lone < is not a tag")
        check(!Sanitize.text("<script>alert(1)</script>Pasta").contains("<"), "script tags stripped")
        check(Sanitize.text("e\u{0301}") == "\u{00E9}", "unicode normalised to NFC")

        // Sanitize.number
        check(Sanitize.number("1,5") == 1.5 && Sanitize.number(" 2 ") == 2 && Sanitize.number(".5") == 0.5, "decimal formats")
        check(Sanitize.number("abc") == nil && Sanitize.number("1e9") == nil && Sanitize.number("-3") == nil, "non-numbers rejected")
        check(Sanitize.number("") == nil && Sanitize.number("12345678") == nil && Sanitize.number("1.2.3") == nil, "empty / huge / malformed")

        // Titles
        check(Validate.recipeTitle("").message == "Give your recipe a name", "empty title")
        check(Validate.recipeTitle("a").message != nil, "one-letter title too short")
        check(Validate.recipeTitle("123").message != nil, "digits-only title")
        check(Validate.recipeTitle(String(repeating: "a", count: 121)).message != nil, "121-char title too long")
        check(Validate.recipeTitle(String(repeating: "a", count: 120)).isValid, "120-char title ok")
        check(Validate.recipeTitle("  Paneer   Tikka  ").value == "Paneer Tikka", "title cleaned")

        // Ingredients & steps
        check(Validate.ingredientLine("").isValid, "empty ingredient line is dropped, not an error")
        check(Validate.ingredientLine("200 g").message != nil, "amount without a name")
        check(Validate.ingredientLine("2 eggs").isValid && Validate.ingredientLine("salt to taste").isValid, "normal lines")
        check(Validate.ingredientLine(String(repeating: "x", count: 201)).message != nil, "201-char ingredient")
        check(Validate.stepText(String(repeating: "Stir. ", count: 400)).message != nil, "2,400-char step too long")
        check(Validate.stepText("Simmer for 10 minutes").isValid, "normal step")

        // Links
        check(Validate.link("instagram.com/reel/abc").url?.absoluteString == "https://instagram.com/reel/abc", "scheme added")
        check(Validate.link("Look https://www.tiktok.com/@chef/video/123?lang=en wow").url?.host() == "www.tiktok.com", "link pulled out of text")
        for bad in ["http://localhost:8080/x", "https://192.168.1.10/r", "https://10.0.0.1", "https://[::1]/x", "https://100.64.0.1",
                    "https://172.20.3.4", "https://printer.local/x", "https://127.0.0.1"] {
            check(Validate.link(bad).url == nil, "private host rejected: \(bad)")
        }
        check(Validate.link("https://user:pass@site.com/x").message?.contains("password") == true, "credentials rejected")
        check(Validate.link("https://site.com:8080/x").url == nil, "odd port rejected")
        check(Validate.link("ftp://site.com/x").url == nil, "ftp rejected")
        check(Validate.link("not a link").url == nil && Validate.link("").message != nil, "garbage / empty")
        check(Validate.link("https://172.32.0.1/x").url != nil, "172.32.x is public")
        check(Validate.link("https://" + String(repeating: "a", count: 2050) + ".com").url == nil, "over-long link")
        check(Validate.link("https://www.allrecipes.com/recipe/1/pancakes/").url != nil, "normal recipe site")

        // Pasted text
        check(Validate.pastedRecipe("short").message != nil, "too short")
        check(Validate.pastedRecipe("Tomato soup with basil and cream").isValid, "ok paste")
        check(Validate.pastedRecipe(String(repeating: "word ", count: 4001)).message != nil, "20,005 chars too long")
        check(Validate.pastedRecipe("1234567890 1234567890 12345").message != nil, "numbers only")

        // Items, amounts, targets, lists
        check(Validate.itemName("2 lemons").isValid && Validate.itemName("").message != nil && Validate.itemName("123").message != nil, "item names")
        check(Validate.quantity("").value == nil && Validate.quantity("").message == nil, "empty amount is fine")
        check(Validate.quantity("1,5").value == 1.5 && Validate.quantity("2").value == 2, "amounts")
        check(Validate.quantity("0").message != nil && Validate.quantity("abc").message != nil && Validate.quantity("200000").message != nil, "bad amounts")
        let calories = Validate.integer("2000", field: "Calories", range: 800...6000)
        check(calories.value == 2000 && calories.message == nil, "calories ok")
        check(Validate.integer("50", field: "Calories", range: 800...6000).message != nil, "calories too low")
        check(Validate.integer("2k", field: "Calories", range: 800...6000).message != nil && Validate.integer("-5", field: "Calories", range: 800...6000).message != nil, "calories malformed")
        check(Validate.integer("", field: "Calories", range: 800...6000) == (nil, nil), "empty target is fine")
        let dislikes = Validate.list("mushrooms, olives and coriander", field: "Dislikes")
        check(dislikes.items == ["mushrooms", "olives", "coriander"] && dislikes.message == nil, "list split: \(dislikes.items)")
        check(Validate.list((1...21).map { "item\($0)x" }.joined(separator: ","), field: "Dislikes").message != nil, "too many items")
        check(Validate.list("abc, 123", field: "Dislikes").message != nil, "non-food item")
        check(Validate.list(String(repeating: "a", count: 41), field: "Dislikes").message != nil, "item too long")
        check(Validate.personName("Anaya").isValid && Validate.personName(" ").message != nil && Validate.personName("42").message != nil, "names")

        // Whole recipe
        let good = RecipeDraftFields(title: "Dal tadka", servings: 4, minutes: 30, ingredients: ["1 cup toor dal", ""], steps: ["Boil the dal."])
        check(Validate.recipe(good) == nil, "valid recipe: \(Validate.recipe(good) ?? "")")
        var bad = good
        bad.ingredients = ["", " "]
        check(Validate.recipe(bad) == "Add at least one ingredient", "needs an ingredient")
        bad = good
        bad.servings = 0
        check(Validate.recipe(bad)?.contains("Servings") == true, "servings range")
        bad = good
        bad.ingredients = ["200 g"]
        check(Validate.recipe(bad)?.contains("name") == true, "ingredient without a name")
        bad = good
        bad.minutes = 5000
        check(Validate.recipe(bad) != nil, "time over 24 h")

        // RecipeDraft.sanitized — the guard before anything is stored
        var draft = RecipeDraft()
        draft.title = "  <i>Best</i>   Pasta\u{200B} "
        draft.servings = 0
        draft.prepMinutes = -5
        draft.cookMinutes = 99_999
        draft.mealTypes = ["Dinner", "brunch"]
        draft.tags = ["quick", "quick", " ", String(repeating: "t", count: 40)]
        draft.sourceURL = "javascript:alert(1)"
        draft.imageURL = "https://example.com/a.jpg"
        var nan = DraftIngredient(line: "")
        nan.text = ""
        nan.name = ""
        var weird = DraftIngredient(line: "2 eggs")
        weird.quantity = .nan
        draft.ingredients = [nan, weird, DraftIngredient(line: "200 g spaghetti")]
        draft.steps = [DraftStep(text: "  "), DraftStep(text: "Boil water", timerSeconds: 999_999)]
        draft.nutrition = DraftNutrition(calories: .infinity, protein: -3, matched: 5, total: 2)
        let clean = draft.sanitized()
        check(clean.title == "Best Pasta", "title sanitised: \(clean.title)")
        check(clean.servings == 1 && clean.prepMinutes == 0 && clean.cookMinutes == 2880, "numbers clamped")
        check(clean.mealTypes == ["dinner"], "meal types filtered: \(clean.mealTypes)")
        check(clean.tags == ["quick", String(repeating: "t", count: 30)], "tags cleaned: \(clean.tags)")
        check(clean.sourceURL == nil && clean.imageURL == "https://example.com/a.jpg", "only web links kept")
        check(clean.ingredients.count == 2 && clean.ingredients[0].quantity == nil, "empty dropped, NaN amount removed")
        check(clean.steps.count == 1 && clean.steps[0].timerSeconds == 86_400, "empty step dropped, timer clamped")
        check(clean.nutrition?.calories == 0 && clean.nutrition?.protein == 0 && clean.nutrition?.total == 5, "nutrition clamped")
    }
}
