import Foundation

@main
struct CustomizationPreferencesCheck {
    static func main() throws {
        let options = ["None known", "Wheat", "Gluten"]
        var preferences = CustomizationPreferences()
        preferences.select("None known", for: "allergies", options: options, multiple: true, exclusive: "None known")
        preferences.select("Wheat", for: "allergies", options: options, multiple: true, exclusive: "None known")
        preferences.select("Gluten", for: "allergies", options: options, multiple: true, exclusive: "None known")
        assert(preferences.choices["allergies"] == ["Wheat", "Gluten"])
        preferences.select("None known", for: "allergies", options: options, multiple: true, exclusive: "None known")
        assert(preferences.choices["allergies"] == ["None known"])

        preferences.notes["otherAllergies"] = "Sesame"
        let saved = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(CustomizationPreferences.self, from: saved)
        assert(restored == preferences)
    }
}
