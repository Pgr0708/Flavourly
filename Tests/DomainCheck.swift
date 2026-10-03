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

    /// The learning engine: habits from activity, mood fit, and the effect on ranking.
    static func habits() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 19))! // Wednesday 7pm
        func at(daysAgo: Double, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -Int(daysAgo), to: calendar.startOfDay(for: now))!
            return calendar.date(byAdding: .hour, value: hour, to: day)!
        }
        var log: [ActivityRecord] = []
        // Weekday evenings: quick dinners (20 min stated, really 25), usually tired.
        for day in [1.0, 2, 3, 6, 8, 9] {
            log.append(ActivityRecord(kind: .cookStart, at: at(daysAgo: day, hour: 19), recipeKey: "dal-\(day)", value: 20))
            log.append(ActivityRecord(kind: .cookFinish, at: at(daysAgo: day, hour: 19).addingTimeInterval(25 * 60), recipeKey: "dal-\(day)", value: 25))
            log.append(ActivityRecord(kind: .mood, at: at(daysAgo: day, hour: 18), mood: .tired))
        }
        log.append(ActivityRecord(kind: .search, at: at(daysAgo: 1, hour: 12), text: "easy paneer curry"))
        log.append(ActivityRecord(kind: .search, at: at(daysAgo: 2, hour: 12), text: "paneer"))
        log.append(ActivityRecord(kind: .skip, at: at(daysAgo: 1, hour: 18), recipeKey: "lasagne"))
        log.append(ActivityRecord(kind: .skip, at: at(daysAgo: 3, hour: 18), recipeKey: "lasagne"))
        let habits = Habits.learn(from: log, now: now, calendar: calendar)
        check(habits.usualMinutes(at: now, calendar: calendar).map { (23...27).contains($0) } == true,
              "weekday evenings: 20 min recipes taking 25 → usual ~25 min, got \(String(describing: habits.usualMinutes(at: now, calendar: calendar)))")
        check(abs(habits.pace - 1.25) < 0.05, "pace learned from real cooking time: \(habits.pace)")
        check(habits.likelyMood(at: now, calendar: calendar)?.mood == .tired, "tired is the usual weekday-evening mood")
        check(habits.usualDinnerHour == 19, "usual dinner hour 7pm: \(String(describing: habits.usualDinnerHour))")
        check(habits.topSearches().first == "paneer", "\"paneer\" is the top search; \"easy\" is ignored: \(habits.topSearches())")
        let weekendMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9))!
        check(habits.likelyMood(at: weekendMorning, calendar: calendar) == nil, "no mood guessed where there's no history")

        let quick = RecipeFacts(id: "quick-paneer", title: "Paneer bhurji", ingredientNames: ["paneer", "onion"], minutes: 20, slots: [.dinner])
        let slow = RecipeFacts(id: "lasagne", title: "Lasagne", ingredientNames: ["pasta", "beef"], minutes: 90, slots: [.dinner])
        let quickBoost = habits.boost(for: quick, mood: .tired, at: now, calendar: calendar)
        let slowBoost = habits.boost(for: slow, mood: .tired, at: now, calendar: calendar)
        check(quickBoost.boost > 1.5 && slowBoost.boost < -1, "tired weekday evening: quick paneer up, skipped 90-min lasagne down (\(quickBoost.boost), \(slowBoost.boost))")
        check(quickBoost.reason == "Easy for a tired day", "the mood is the main reason: \(String(describing: quickBoost.reason))")
        check(habits.boost(for: quick, mood: nil, at: now, calendar: calendar).reason?.contains("paneer") == true, "without a mood, the search explains it")

        var context = RankContext()
        context.now = now
        context.habits = habits
        context.mood = .tired
        let ranked = Recommender.rank([slow, quick], context)
        check(ranked.first?.facts.id == "quick-paneer", "ranking follows habits and mood")
        check(Habits.moodFit(slow, mood: .comfort, haystack: "lasagne pasta beef", taste: TasteProfile()).0 > 0, "lasagne is comfort food")
        check(Habits.learn(from: [], now: now).isEmpty, "no activity → nothing learned")
        // More moods.
        let congee = RecipeFacts(id: "congee", title: "Congee", ingredientNames: ["rice", "ginger", "water"], minutes: 40, slots: [.dinner])
        let butterChicken = RecipeFacts(id: "bc", title: "Butter chicken", ingredientNames: ["chicken", "butter", "cream"], minutes: 50, slots: [.dinner], cuisine: "Indian")
        let fit = { (r: RecipeFacts, m: Mood) in Habits.moodFit(r, mood: m, haystack: ([r.title] + r.ingredientNames).joined(separator: " ").lowercased(), taste: TasteProfile(), localCuisine: "Indian").0 }
        check(fit(congee, .unwell) > 0.5 && fit(butterChicken, .unwell) < 0, "unwell: congee yes, butter chicken no")
        check(fit(congee, .cozy) > 0.5, "rainy day: congee is cozy")
        check(fit(butterChicken, .homesick) > 0.5 && fit(congee, .homesick) <= 0, "homesick: home cuisine first")
        check(fit(quick, .lazy) > 0 && fit(slow, .lazy) < 0, "lazy: 20-min paneer over 90-min lasagne")
        check(Mood.allCases.count == 16 && Set(Mood.allCases.map(\.label)).count == 16, "16 distinct moods")

        // Home order follows the moment.
        let morning = HomeLayout.order(at: Moment(weekend: false, part: .morning), hasTonight: true, expiringToday: false, cooksAtThisMoment: true)
        check(morning.first == .rightNow && morning[1] == .forYou, "mornings: the pick and breakfast ideas first: \(morning)")
        let weeknight = HomeLayout.order(at: Moment(weekend: false, part: .evening), hasTonight: true, expiringToday: false, cooksAtThisMoment: true)
        check(weeknight.prefix(3) == [.tonight, .rightNow, .cookNow], "weekday evenings: tonight's meal, the pick, Cook Now: \(weeknight)")
        let weekend = HomeLayout.order(at: Moment(weekend: true, part: .midday), hasTonight: false, expiringToday: false, cooksAtThisMoment: true)
        check(weekend.prefix(3) == [.rightNow, .tryNew, .world] && !weekend.contains(.tonight), "weekends: new dishes and world kitchens: \(weekend)")
        let expiring = HomeLayout.order(at: Moment(weekend: true, part: .midday), hasTonight: false, expiringToday: true, cooksAtThisMoment: true)
        check(expiring[1] == .useSoon, "food going off today comes second: \(expiring)")
        let rarely = HomeLayout.order(at: Moment(weekend: false, part: .evening), hasTonight: false, expiringToday: false, cooksAtThisMoment: false)
        check(rarely.last == .cookNow, "rarely cooks at this time: Cook Now moves down: \(rarely)")
        check(Set(weekend + [.tonight]) == Set(HomeSection.allCases), "every section has a place")
    }

    static func main() {
        habits()
        var tagged = RecipeDraft(); tagged.title = "Aash"; tagged.tags = ["null", "Kabul", "None"]
        check(tagged.sanitized().tags == ["Kabul"], "\"null\" text is not a tag: \(tagged.sanitized().tags)")
        // Photo credits travel in the URL fragment (server: withCredit in services.js).
        let pexels = ImageCredit("https://images.pexels.com/2.jpg#credit=Photo%20by%20Asha%20on%20Pexels&credit_url=https%3A%2F%2Fpexels.com%2Fphoto%2F2")
        check(pexels?.text == "Photo by Asha on Pexels" && pexels?.link?.absoluteString == "https://pexels.com/photo/2", "pexels credit parsed: \(String(describing: pexels))")
        check(ImageCredit("https://api.example.com/images/a.jpg#credit=AI-generated%20image")?.link == nil, "AI credit has no link")
        check(ImageCredit("https://img.example.com/a.jpg") == nil, "no fragment → no credit")
        check(ImageCredit("https://x.com/a.jpg#credit=Hi&credit_url=javascript%3Aalert(1)")?.link == nil, "only http(s) credit links")
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
        newRules()
        learning()

        if failures == 0 {
            print("DomainCheck passed")
        } else {
            print("DomainCheck: \(failures) failure(s)")
            exit(1)
        }
    }

    // MARK: - Sanitising & validation (what users type, paste or share)

    static func learning() {
        // Prices: unit conversion, counts, mismatches, coverage, staples
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let onions = PricePoint(key: FoodText.key("onions"), name: "Onions", price: 60, quantity: 1, unit: "kg", currency: "INR", date: day)
        check(abs((PriceBook.cost(250, unit: "g", at: onions) ?? 0) - 15) < 0.001, "250 g of onions at ₹60/kg = ₹15")
        let eggs = PricePoint(key: FoodText.key("eggs"), name: "Eggs", price: 84, quantity: 12, unit: "", currency: "INR", date: day)
        check(abs((PriceBook.cost(3, unit: "piece", at: eggs) ?? 0) - 21) < 0.001, "3 eggs at ₹84 a dozen = ₹21")
        check(PriceBook.cost(2, unit: "cup", at: onions) == nil, "cups vs kg is never guessed")
        let milk = PricePoint(key: FoodText.key("milk"), name: "Milk", price: 1.2, quantity: 1, unit: "l", currency: "USD", date: day)
        check(abs((PriceBook.cost(250, unit: "ml", at: milk) ?? 0) - 0.3) < 0.001, "ml vs l")
        let prices = [onions.key: onions, eggs.key: eggs]
        let staple: (String) -> Bool = { GroceryBuilder.staples.contains(FoodText.key($0)) }
        let omelette = PriceBook.estimate(ingredients: [("onions", 100, "g"), ("eggs", 4, ""), ("salt", 1, "tsp")], servings: 2, prices: prices, isStaple: staple)
        check(omelette.map { abs($0.perServing - (6 + 28) / 2) < 0.001 && $0.total == 2 } == true, "per-serving cost, salt ignored: \(String(describing: omelette))")
        let mostlyUnknown = PriceBook.estimate(ingredients: [("onions", 100, "g"), ("paneer", 200, "g"), ("cream", 100, "ml")], servings: 2, prices: prices, isStaple: staple)
        check(mostlyUnknown == nil, "no cost until 70% of ingredients are priced")
        check(Validate.price("45").value == 45 && Validate.price("3,49").value == 3.49 && Validate.price("").value == nil, "price parsing")
        check(Validate.price("0").message != nil && Validate.price("abc").message != nil && Validate.price("99999999").message != nil, "bad prices")

        // Taste: learned from cooking and ratings, fading with age
        let paneer = RecipeFacts(id: "p", title: "Paneer tikka", ingredientNames: ["200 g paneer", "1 onion"], minutes: 30, slots: [.dinner], cuisine: "Indian")
        let pasta = RecipeFacts(id: "s", title: "Spaghetti", ingredientNames: ["200 g spaghetti", "1 can tomatoes"], minutes: 20, slots: [.dinner], cuisine: "Italian")
        let recent = Date(timeIntervalSince1970: 1_790_000_000)
        var signals = [TasteProfile.Signal(facts: paneer, cookedCount: 4, rating: 5, isFavorite: true, lastCooked: recent),
                       TasteProfile.Signal(facts: pasta, cookedCount: 1, rating: 1, isFavorite: false, lastCooked: recent)]
        for i in 0..<4 {
            signals.append(TasteProfile.Signal(facts: RecipeFacts(id: "x\(i)", title: "Dal \(i)", ingredientNames: ["100 g toor dal"], minutes: 30, slots: [.dinner], cuisine: "Indian"),
                                               cookedCount: 2, rating: 4, isFavorite: false, lastCooked: recent))
        }
        let taste = TasteProfile.learn(from: signals, now: recent)
        let newIndian = RecipeFacts(id: "n", title: "Paneer butter masala", ingredientNames: ["250 g paneer", "2 tomatoes"], minutes: 40, slots: [.dinner], cuisine: "Indian")
        let newItalian = RecipeFacts(id: "i", title: "Penne", ingredientNames: ["200 g spaghetti"], minutes: 20, slots: [.dinner], cuisine: "Italian")
        check(taste.score(newIndian).boost > 0.5 && taste.score(newItalian).boost < 0, "likes Indian/paneer, not that pasta: \(taste.score(newIndian).boost) / \(taste.score(newItalian).boost)")
        check(taste.score(newIndian).reason != nil, "explains why")
        let old = TasteProfile.learn(from: signals.map { var s = $0; s.lastCooked = recent.addingTimeInterval(-730 * 86_400); return s }, now: recent)
        check(old.score(newIndian).boost < taste.score(newIndian).boost + 0.001, "two-year-old habits count less")
        check(TasteProfile.learn(from: [], now: recent).isEmpty, "new cook: no learned bias")
        var learned = RankContext()
        learned.taste = taste
        check(Recommender.rank([newItalian, newIndian], learned).first?.id == "n", "learned taste reorders ideas")

        // Cook Now knows amounts: 100 g paneer doesn't cover a 400 g recipe
        let tikka = RecipeFacts(id: "t", title: "Paneer tikka", ingredientNames: ["400 g paneer", "2 onions"], minutes: 30, slots: [.dinner])
        var pantryContext = RankContext()
        pantryContext.pantry = [PantrySignal(key: "paneer", name: "Paneer", daysLeft: nil, quantity: 100, unit: "g"),
                                PantrySignal(key: "onion", name: "Onions", daysLeft: nil, quantity: 6, unit: "")]
        let short = Recommender.evaluate(tikka, pantryContext)
        check(short?.missing.contains { $0.lowercased().contains("paneer") } == true && short?.have == ["Onions"], "too little paneer counts as missing: \(String(describing: short?.missing))")
        pantryContext.pantry[0].quantity = 0.5
        pantryContext.pantry[0].unit = "kg"
        check(Recommender.evaluate(tikka, pantryContext)?.missing.isEmpty == true, "0.5 kg covers 400 g")

        // Planner: steer towards the day's calorie target
        let light = RecipeFacts(id: "light", title: "Light", ingredientNames: ["1 egg"], minutes: 10, slots: [.dinner], protein: 25, calories: 650)
        let heavy = RecipeFacts(id: "heavy", title: "Heavy", ingredientNames: ["1 egg"], minutes: 10, slots: [.dinner], rating: 5, protein: 25, calories: 1600)
        var options = PlannerOptions()
        options.leftoversForLunch = false
        options.dailyCalories = 1900
        let monday = Date(timeIntervalSince1970: 1_790_000_000)
        let picks = Planner.fill(empty: [PlanSlot(day: monday, slot: .dinner)], existing: [:], recipes: [heavy, light], base: RankContext(), options: options)
        check(picks.first?.recipeID == "light", "planner picks the meal that fits the day's calories")
    }

    static func newRules() {
        // Barcodes (GTIN check digit)
        check(Validate.barcode("8901063010321").value == "8901063010321", "valid EAN-13")
        check(Validate.barcode("4006381 333931").value == "4006381333931", "spaces ignored")
        check(Validate.barcode("96385074").value == "96385074", "valid EAN-8")
        check(Validate.barcode("8901063010322").message != nil, "wrong check digit")
        check(Validate.barcode("12345").message != nil && Validate.barcode("").message != nil, "too short / empty")
        check(Validate.barcode("89010630103a1").message != nil && Validate.barcode("٨٩٠١٠٦٣٠١٠٣٢١").message != nil, "letters / non-ASCII digits")

        // Packaged-food allergens (Open Food Facts tags become plain words)
        var nutAllergy = FoodProfile()
        nutAllergy.add(person: "Ravi", allergies: ["Tree nuts"], diets: [], dislikes: [], mild: false)
        let nutella = ["milk", "nuts", "soy", "may contain gluten", "Sugar, palm oil, hazelnuts 13%, skimmed milk powder, cocoa, soy lecithin"]
        check(FoodRules.check(ingredients: nutella, profile: nutAllergy).isBlocked, "scanned product with hazelnuts is blocked for a nut allergy")
        var milkAllergy = FoodProfile()
        milkAllergy.add(person: "Mia", allergies: ["Milk"], diets: [], dislikes: [], mild: false)
        check(!FoodRules.check(ingredients: nutella, profile: milkAllergy).allergenIssues.isEmpty, "…and flagged for a milk allergy")

        // Difficulty & equipment from the recipe itself
        check(RecipeTraits.difficulty(steps: ["Toss everything together."], ingredientCount: 5, minutes: 10) == .easy, "simple salad is easy")
        let bread = (1...12).map { "Step \($0): knead and proof the dough, then bake." }
        check(RecipeTraits.difficulty(steps: bread, ingredientCount: 12, minutes: 180) == .hard, "long bread is challenging")
        check(RecipeTraits.equipment(steps: ["Preheat the oven to 200°C.", "Roast for 30 minutes."]) == [.oven], "oven")
        check(RecipeTraits.equipment(steps: ["Cook dal in a pressure cooker for 3 whistles.", "Temper in a pan."]).isSuperset(of: [.pressureCooker, .stovetop]), "pressure cooker + pan")
        check(RecipeTraits.equipment(steps: ["Mix yogurt with fruit.", "Top with seeds."]) == [.noCook], "no cooking")
        check(RecipeTraits.equipment(steps: ["Air fryer at 180°C for 12 minutes."]).contains(.airFryer), "air fryer")
        check(!RecipeTraits.equipment(steps: ["Add panch phoron and potatoes to the bowl."]).contains(.stovetop), "'pan'/'pot' inside words don't count")
        check(RecipeTraits.equipment(steps: ["Grilled the paneer, then fried the onions in two pans."]).contains(.stovetop), "word endings still count")
        check(Difficulty(skill: "Just starting") == .easy && Difficulty(skill: "Very experienced") == nil, "skill mapping")

        // Keto / low carb without nutrition
        var keto = FoodProfile()
        keto.add(person: "Asha", allergies: [], diets: ["Keto"], dislikes: [], mild: false)
        check(FoodRules.check(ingredients: ["300 g spaghetti", "2 eggs"], profile: keto).needsCheck, "pasta flagged for keto when carbs unknown")
        check(!FoodRules.check(ingredients: ["300 g cauliflower rice", "2 eggs"], profile: keto).needsCheck, "cauliflower rice is fine")
        check(!FoodRules.check(ingredients: ["300 g spaghetti"], profile: keto, carbsPerServing: 15).needsCheck, "known low carbs win over the word")

        // Ranking: strict allergens, skill, nutrition limits
        var nuts = FoodProfile()
        nuts.add(person: "Ravi", allergies: ["Tree nuts"], diets: [], dislikes: [], mild: false)
        let pesto = RecipeFacts(id: "pesto", title: "Pesto pasta", ingredientNames: ["3 tbsp pesto", "200 g pasta"], minutes: 20, slots: [.dinner])
        var context = RankContext()
        context.profile = nuts
        let relaxed = Recommender.evaluate(pesto, context)
        context.strictAllergens = true
        check(relaxed != nil || FoodRules.check(ingredients: pesto.ingredientNames, profile: nuts).isBlocked, "manual browsing still shows 'likely' dishes")
        check(Recommender.evaluate(pesto, context) == nil, "automatic plans skip 'likely' allergens")

        let easy = RecipeFacts(id: "e", title: "Easy", ingredientNames: ["2 eggs"], minutes: 10, slots: [.dinner], difficulty: .easy)
        let hard = RecipeFacts(id: "h", title: "Hard", ingredientNames: ["2 eggs"], minutes: 10, slots: [.dinner], difficulty: .hard)
        var beginner = RankContext()
        beginner.skillCap = .easy
        check(Recommender.rank([hard, easy], beginner).first?.id == "e", "beginners see easy recipes first")

        var light = RankContext()
        light.maxCalories = 500
        light.minProtein = 20
        let heavy = RecipeFacts(id: "x", title: "Heavy", ingredientNames: ["2 eggs"], minutes: 10, slots: [.dinner], protein: 30, calories: 900)
        let lean = RecipeFacts(id: "y", title: "Lean", ingredientNames: ["2 eggs"], minutes: 10, slots: [.dinner], protein: 30, calories: 400)
        let lowProtein = RecipeFacts(id: "z", title: "Low", ingredientNames: ["2 eggs"], minutes: 10, slots: [.dinner], protein: 5, calories: 300)
        check(Recommender.rank([heavy, lean, lowProtein], light).map(\.id) == ["y"], "calorie cap and protein floor")
    }

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
