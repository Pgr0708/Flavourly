import Foundation

@main
struct HomeDataCheck {
    static func main() throws {
        assert(HomeMoment(hour: 4).imageName == "HomeNight")
        assert(HomeMoment(hour: 5).imageName == "HomeMorning")
        assert(HomeMoment(hour: 12).imageName == "HomeAfternoon")
        assert(HomeMoment(hour: 18).imageName == "HomeNight")

        var data = HomeData()
        data.setMeal("Pasta", for: "Mon")
        data.toggleMealLock(for: "Mon")
        data.setMeal("Soup", for: "Mon")
        assert(data.plannedDayCount == 1)
        assert(data.weeklyMeals["Mon"]?.isLocked == true)
        data.addGroceryItem("  Tomatoes  ")
        assert(data.groceryItems.first?.title == "Tomatoes")
        assert(!data.addRecipeLink(title: "Bad", url: "javascript:alert(1)"))
        assert(data.addRecipeLink(title: "", url: "https://example.com/recipe"))
        assert(data.recipeLinks.first?.title == "example.com")

        let saved = try JSONEncoder().encode(data)
        let restored = try JSONDecoder().decode(HomeData.self, from: saved)
        assert(restored == data)
    }
}
