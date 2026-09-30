import Foundation

enum HomeMoment {
    case morning, afternoon, night

    init(hour: Int) {
        if (5..<12).contains(hour) {
            self = .morning
        } else if (12..<18).contains(hour) {
            self = .afternoon
        } else {
            self = .night
        }
    }

    var greeting: String {
        switch self {
        case .morning: "Good Morning"
        case .afternoon: "Good Afternoon"
        case .night: "Good Evening"
        }
    }

    var imageName: String {
        switch self {
        case .morning: "HomeMorning"
        case .afternoon: "HomeAfternoon"
        case .night: "HomeNight"
        }
    }
}

struct GroceryItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var isChecked = false
}

struct SavedRecipeLink: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
}

struct PlannedMeal: Codable, Equatable {
    var title: String
    var isLocked = false
}

struct HomeData: Codable, Equatable {
    var groceryItems: [GroceryItem] = []
    var recipeLinks: [SavedRecipeLink] = []
    var savedIdeaIDs: [String] = []
    var weeklyMeals: [String: PlannedMeal] = [:]

    var plannedDayCount: Int {
        weeklyMeals.values.filter { !$0.title.isEmpty }.count
    }

    mutating func setMeal(_ title: String, for day: String) {
        let cleanTitle = String(title.prefix(80))
        if cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            weeklyMeals.removeValue(forKey: day)
        } else {
            weeklyMeals[day] = PlannedMeal(title: cleanTitle, isLocked: weeklyMeals[day]?.isLocked ?? false)
        }
    }

    mutating func toggleMealLock(for day: String) {
        guard var meal = weeklyMeals[day] else { return }
        meal.isLocked.toggle()
        weeklyMeals[day] = meal
    }

    mutating func addGroceryItem(_ title: String) {
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleanTitle.isEmpty else { return }
        groceryItems.append(GroceryItem(title: cleanTitle))
    }

    mutating func addRecipeLink(title: String, url: String) -> Bool {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: cleanURL),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty else { return false }
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        recipeLinks.append(SavedRecipeLink(title: cleanTitle.isEmpty ? host : cleanTitle, url: cleanURL))
        return true
    }

    mutating func toggleSavedIdea(_ id: String) {
        if savedIdeaIDs.contains(id) {
            savedIdeaIDs.removeAll { $0 == id }
        } else {
            savedIdeaIDs.append(id)
        }
    }
}
