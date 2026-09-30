//
//  PaywallViewModel.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import Foundation
import SwiftUI
import RevenueCat
internal import Combine


class ProViewModel : BaseViewModel {
    @Published var selectedPackage : Package?
    @Published var allPackages = [Package]()

    func getOffering() {
        startLoading()
        Purchases.shared.getOfferings { (offerings, error) in
            self.stopLoading()
            if let offering = offerings?.current , error == nil {
                self.allPackages = offering.availablePackages
                self.selectedPackage = self.allPackages.first(where: {$0.packageType == .lifetime})
            }
        }
    }

    func makePurchases(completion: @escaping ()->()) {
        startLoading()
        if let package = self.selectedPackage {
            Purchases.shared.purchase(package: package) { (transaction, customerInfo, error, userCancelled) in
                self.checkUserIsPro(customerInfo: customerInfo)
                self.stopLoading()
                if self.isPro {
                    completion()
                }
            }
        }
    }

    func restorePurchases(completion: @escaping ()->()) {
            startLoading()
            Purchases.shared.restorePurchases { customerInfo, error in
                self.checkUserIsPro(customerInfo: customerInfo)
                self.stopLoading()
                if self.isPro {
                    completion()
                }
            }
        }

}

