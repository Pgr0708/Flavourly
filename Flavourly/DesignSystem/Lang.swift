import SwiftUI

/// Translations for text that isn't a literal `Text("…")`: component titles, banners, validator
/// messages. Looks up the language picked in Flavourly (not only the phone's), from Localizable.xcstrings.
enum Lang {
    /// Flavourly's language codes → the app's .lproj folders.
    static func lproj(for code: String) -> String {
        ["zh": "zh-Hans", "pt": "pt-BR"][code] ?? code
    }

    private static var bundles: [String: Bundle] = [:]

    private static func bundle(_ identifier: String) -> Bundle {
        if let hit = bundles[identifier] { return hit }
        let candidates = [identifier, lproj(for: String(identifier.prefix { $0 != "-" && $0 != "_" }))]
        let found = candidates.lazy.compactMap { Bundle.main.path(forResource: $0, ofType: "lproj") }.first.flatMap(Bundle.init(path:)) ?? .main
        bundles[identifier] = found
        return found
    }

    /// For views: pass `@Environment(\.locale)` so the text redraws the moment the language changes.
    static func text(_ key: String, _ locale: Locale) -> String {
        guard !key.isEmpty else { return key }
        return bundle(locale.identifier).localizedString(forKey: key, value: key, table: nil)
    }

    /// For UIKit (banners) and anything outside a view.
    static func text(_ key: String) -> String {
        text(key, Locale(identifier: lproj(for: SettingsManager.shared.languageCode)))
    }
}
