import CoreData
import SwiftUI

/// Everyone at the table: "me" comes from the setup quiz, the rest from Household.
struct Person: Identifiable, Hashable {
    static let meID = "me"

    let id: String
    let name: String
    let colorHex: String
    let allergies: [String]
    let diets: [String]
    let dislikes: [String]
    let goals: [String]
    let mildOnly: Bool
    let portion: Double
    let calorieTarget: Int
    let proteinTarget: Int
    let slots: Set<MealSlot>

    var initial: String { String(name.prefix(1)).uppercased() }
    var color: Color { Color(hex: colorHex) }
    var isMe: Bool { id == Self.meID }
    var wantsHighProtein: Bool { goals.contains { $0.lowercased().contains("protein") || $0.lowercased().contains("muscle") } }
}

@MainActor
enum People {
    static func me(_ settings: SettingsManager = .shared) -> Person {
        let prefs = settings.customizationPreferences
        var allergies = (prefs.choices["allergies"] ?? []).filter { $0 != "None known" && $0 != "Other" }
        allergies += splitList(prefs.notes["otherAllergies"])
        let calories = Validate.integer(prefs.notes["calories"] ?? "", field: "Calories", range: Validate.Target.calories).value ?? 0
        let protein = Validate.integer(prefs.notes["protein"] ?? "", field: "Protein", range: Validate.Target.protein).value ?? 0
        return Person(
            id: Person.meID, name: settings.displayName, colorHex: "#155634",
            allergies: allergies,
            diets: (prefs.choices["diet"] ?? []).filter { $0 != "No preference" },
            dislikes: splitList(prefs.notes["dislikes"]),
            goals: prefs.choices["goals"] ?? [],
            mildOnly: prefs.choices["spice"]?.contains("Mild") ?? false,
            portion: 1, calorieTarget: calories, proteinTarget: protein,
            slots: Set(MealSlot.allCases)
        )
    }

    static func members(_ context: NSManagedObjectContext = CoreDataManager.shared.context) -> [HouseholdMember] {
        let request = NSFetchRequest<HouseholdMember>(entityName: "HouseholdMember")
        request.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    static func all() -> [Person] {
        [me()] + members().map(person)
    }

    static func person(_ member: HouseholdMember) -> Person {
        var slots = Set<MealSlot>([.snack])
        if member.eatsBreakfast { slots.insert(.breakfast) }
        if member.eatsLunch { slots.insert(.lunch) }
        if member.eatsDinner { slots.insert(.dinner) }
        return Person(
            id: member.uuid?.uuidString ?? member.objectID.uriRepresentation().absoluteString,
            name: member.displayName, colorHex: member.colorHex ?? "#C7631F",
            allergies: Recipe.split(member.allergies), diets: Recipe.split(member.diets),
            dislikes: Recipe.split(member.dislikes), goals: Recipe.split(member.goals),
            mildOnly: member.spiceLevel == "mild" || member.ageGroup == "child",
            portion: member.portion, calorieTarget: Int(member.calorieTarget), proteinTarget: Int(member.proteinTarget),
            slots: slots
        )
    }

    /// Hard rules for the given eaters (everyone when nil).
    static func profile(for ids: [String]? = nil) -> FoodProfile {
        let everyone = all()
        let eating = ids.map { wanted in everyone.filter { wanted.contains($0.id) } } ?? everyone
        var profile = FoodProfile()
        for person in eating.isEmpty ? [me()] : eating {
            profile.add(person: person.name, allergies: person.allergies, diets: person.diets,
                        dislikes: person.dislikes, mild: person.mildOnly)
        }
        return profile
    }

    /// Default eaters for a slot, e.g. "Anaya eats lunch at school".
    static func defaultEaters(for slot: MealSlot) -> [String] {
        all().filter { $0.slots.contains(slot) }.map(\.id)
    }

    /// Portions for a meal: children count as half, bigger eaters more.
    static func servings(for ids: [String]) -> Int {
        let everyone = all()
        let total = everyone.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.portion }
        return max(1, Int(total.rounded(.up)))
    }

    static func splitList(_ text: String?) -> [String] {
        Validate.list(text ?? "", field: "List", maxItems: 30, maxLength: 60).items.map { String($0.prefix(60)) }
    }
}
