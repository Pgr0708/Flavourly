import Foundation
import HealthKit

/// Writes logged meals to Apple Health. Opt-in only; nothing is read, nothing is used for ads.
@MainActor
final class HealthService {
    static let shared = HealthService()

    private let store = HKHealthStore()
    private let types: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Apple only tells us if we may *write*; denied means the user turned it off in Settings.
    var isDenied: Bool {
        guard isAvailable, let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return false }
        return store.authorizationStatus(for: energy) == .sharingDenied
    }

    var isConnected: Bool {
        guard isAvailable, let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return false }
        return store.authorizationStatus(for: energy) == .sharingAuthorized && SettingsManager.shared.healthSyncEnabled
    }

    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        let share = Set(types.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        do {
            try await store.requestAuthorization(toShare: share, read: [])
        } catch {
            return false
        }
        let granted = !isDenied
        SettingsManager.shared.healthSyncEnabled = granted
        return granted
    }

    func write(_ logs: [MealLog]) {
        guard isConnected, !logs.isEmpty else { return }
        var samples: [HKObject] = []
        for log in logs where !log.syncedToHealth {
            let date = log.date ?? .now
            var parts: Set<HKSample> = []
            func add(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit) {
                guard value > 0, let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
                parts.insert(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date))
            }
            add(.dietaryEnergyConsumed, log.calories, .kilocalorie())
            add(.dietaryProtein, log.protein, .gram())
            add(.dietaryCarbohydrates, log.carbs, .gram())
            add(.dietaryFatTotal, log.fat, .gram())
            guard !parts.isEmpty, let food = HKCorrelationType.correlationType(forIdentifier: .food) else { continue }
            samples.append(HKCorrelation(type: food, start: date, end: date, objects: parts,
                                         metadata: [HKMetadataKeyFoodType: log.title ?? "Meal"]))
            log.syncedToHealth = true
        }
        guard !samples.isEmpty else { return }
        store.save(samples) { success, error in
            if !success {
                Task { @MainActor in
                    DropsManager.showError(title: "Apple Health didn't save", subtitle: error?.localizedDescription)
                }
            }
        }
        Kitchen.save()
    }
}
