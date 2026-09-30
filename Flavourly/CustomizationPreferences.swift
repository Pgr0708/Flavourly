import Foundation

struct CustomizationPreferences: Codable, Equatable {
    var choices: [String: [String]] = [:]
    var notes: [String: String] = [:]

    mutating func select(_ option: String, for key: String, options: [String], multiple: Bool, exclusive: String?) {
        var selected = Set(choices[key] ?? [])
        if !multiple || option == exclusive {
            selected = [option]
        } else {
            if let exclusive { selected.remove(exclusive) }
            if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
        }
        choices[key] = options.filter { selected.contains($0) }
    }
}
