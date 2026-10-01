import UIKit

/// One place for every haptic in the app, so each kind of interaction feels different
/// and the whole thing can be switched off in Settings.
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let notifier = UINotificationFeedbackGenerator()
    private static var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppStorageKeys.hapticsEnabled) as? Bool ?? true
    }

    /// Tabs, segmented controls, pickers.
    static func select() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }

    /// Chips and toggles.
    static func toggle() { impact(.soft, intensity: 0.9) }
    /// Checkboxes, list ticks.
    static func tick() { impact(.light, intensity: 0.8) }
    /// Steppers going up or down.
    static func step() { impact(.light, intensity: 0.55) }
    /// Primary buttons and sheet openers.
    static func primary() { impact(.medium) }
    /// Locks, drags landing, cards snapping into place.
    static func thud() { impact(.rigid) }
    /// Long presses.
    static func longPress() { impact(.heavy) }
    /// Destructive actions (delete, remove).
    static func destructive() {
        impact(.rigid)
        notify(.warning)
    }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        guard isEnabled else { return }
        let generator = impacts[style] ?? UIImpactFeedbackGenerator(style: style)
        impacts[style] = generator
        generator.impactOccurred(intensity: intensity)
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notifier.notificationOccurred(type)
    }
}
