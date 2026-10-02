//
//  BaseViewModel.swift
//  Flavourly
//
//  Created by Minaxi on 16/08/26.
//

import Foundation
import SwiftUI
import RevenueCat
import CoreData
internal import Combine

@MainActor
class BaseViewModel: NSObject, ObservableObject {
    var isPro: Bool {
        get { SettingsManager.shared.isPremium }
        set { SettingsManager.shared.isPremium = newValue }
    }
    @Published var isLoading = false
    @Published var dummy = false
    @Published var isCameraPermission: Bool = true
    @Published var refreshID = UUID()
    static let shared = BaseViewModel()
    
    func startLoading(){
        DispatchQueue.main.async {
            self.isLoading = true
        }
    }
    
    func stopLoading() {
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }
    
    func reset() {
        self.dummy.toggle()
    }
    
    
    // @@@@
    func checkUserIsPro(customerInfo: CustomerInfo?) {
        // Same entitlement ids the server checks (REVENUECAT_ENTITLEMENT=pro,lifetime).
        isPro = ["pro", "lifetime"].contains { customerInfo?.entitlements[$0]?.isActive == true }
    }
    
    func showProSheet(){
        NotificationCenter.default.post(name: NSNotification.proSheet, object: nil)
    }

    func hideProSheet(){
        NotificationCenter.default.post(name: NSNotification.hideProSheet, object: nil)
    }
    
    func hideTabbar(){
        NotificationCenter.default.post(name: NSNotification.hideTabbar, object: nil)
    }
    
    
    func showTabbar(){
        NotificationCenter.default.post(name: NSNotification.showTabbar, object: nil)
    }
    
    func refreshView(){
        NotificationCenter.default.post(name: NSNotification.refresh, object: nil)
    }
}


extension NSNotification {
    static var proSheet = Notification.Name.init("proSheet")
    static var hideProSheet = Notification.Name.init("hideProSheet")
    static var hideTabbar = Notification.Name.init("hideTabbar")
    static var showTabbar = Notification.Name.init("showTabbar")
    static var refresh = Notification.Name.init("refresh")
}
