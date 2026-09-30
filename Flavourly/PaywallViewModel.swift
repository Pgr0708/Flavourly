import RevenueCat
import SwiftUI
internal import Combine

enum PaywallPlan: String, CaseIterable, Identifiable {
    case weekly, monthly, yearly, lifetime

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var period: String {
        switch self {
        case .weekly: return "/ week"
        case .monthly: return "/ month"
        case .yearly: return "/ year"
        case .lifetime: return "once"
        }
    }
    var previewPrice: String {
        switch self {
        case .weekly: return "$4.99"
        case .monthly: return "$9.99"
        case .yearly: return "$39.99"
        case .lifetime: return "$89.99"
        }
    }
    var packageType: PackageType {
        switch self {
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .annual
        case .lifetime: return .lifetime
        }
    }
}

@MainActor
final class ProViewModel: BaseViewModel {
    @Published var selectedPlan: PaywallPlan = .yearly
    @Published private(set) var allPackages: [Package] = []
    @Published var errorMessage: String?

    var isConfigured: Bool { hasRevenueCatAPIKey }

    func package(for plan: PaywallPlan) -> Package? {
        allPackages.first {
            $0.packageType == plan.packageType ||
            $0.identifier.lowercased().contains(plan.rawValue)
        }
    }

    func price(for plan: PaywallPlan) -> String {
        package(for: plan)?.localizedPriceString ?? (isConfigured ? "Unavailable" : plan.previewPrice)
    }

    func getOffering() {
        guard isConfigured else { return }
        startLoading()
        Purchases.shared.getOfferings { offerings, error in
            self.stopLoading()
            if let error {
                self.errorMessage = error.localizedDescription
            }
            self.allPackages = offerings?.current?.availablePackages ?? []
        }
    }

    func makePurchases(completion: @escaping () -> Void) {
        guard let package = package(for: selectedPlan) else {
            errorMessage = isConfigured ? "This plan is not available yet." : "Plans are previews until RevenueCat is connected."
            return
        }
        startLoading()
        Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
            self.stopLoading()
            if let customerInfo {
                self.checkUserIsPro(customerInfo: customerInfo)
            }
            if self.isPro {
                completion()
            } else if let error, !userCancelled {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func restorePurchases(completion: @escaping () -> Void) {
        guard isConfigured else {
            errorMessage = "Restore becomes available when RevenueCat is connected."
            return
        }
        startLoading()
        Purchases.shared.restorePurchases { customerInfo, error in
            self.stopLoading()
            if let customerInfo {
                self.checkUserIsPro(customerInfo: customerInfo)
            }
            if self.isPro {
                completion()
            } else {
                self.errorMessage = error?.localizedDescription ?? "No active purchase was found."
            }
        }
    }
}
