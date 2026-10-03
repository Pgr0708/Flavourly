import CoreLocation
import Foundation

/// Where the cook lives, as "country + state/region" for local food. One coarse reading when asked —
/// never tracking, and only the country code and region name ever leave the phone (never coordinates).
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    struct Place: Equatable {
        let country: String  // ISO code, e.g. "IN"
        let region: String?  // state / province, e.g. "Gujarat"
    }

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { [.denied, .restricted].contains(manager.authorizationStatus) }

    /// Asks for permission the first time (the system popup), then reads the place. Nil when not allowed or unknown.
    func currentPlace() async -> Place? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else { return nil }
        let location: CLLocation? = await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
        guard let location,
              let mark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first,
              let code = mark.isoCountryCode?.uppercased() else { return nil }
        let region = mark.administrativeArea?.trimmingCharacters(in: .whitespaces)
        return Place(country: code, region: region?.isEmpty == false ? region : nil)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            authorizationWaiters.forEach { $0.resume() }
            authorizationWaiters.removeAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { finish(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    private func finish(_ location: CLLocation?) {
        locationWaiters.forEach { $0.resume(returning: location) }
        locationWaiters.removeAll()
    }
}
