//
//  BaseViewModel.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import Foundation
import SwiftUI
import RevenueCat
import CoreData
import AVKit
internal import Combine

@MainActor
class BaseViewModel: NSObject, ObservableObject {
    @EnvironmentObject var settings: SettingsManager
    var isPro: Bool {
        get { settings.isPremium }
        set { settings.isPremium = newValue }
    }
    @Published var isLoading = false
    @Published var isShowDataTransferSheet = false
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
        if customerInfo?.entitlements["pro"]?.isActive == true ||
                customerInfo?.entitlements["lifetime"]?.isActive == true {
            isPro = true
        } else if let date = customerInfo?.latestExpirationDate, date >= Date() {
            isPro = true
        } else {
            isPro = false
        }
    }
    
    func showProSheet(){
        NotificationCenter.default.post(name: NSNotification.proSheet, object: nil)
    }

    func hideProSheet(){
        NotificationCenter.default.post(name: NSNotification.hideProSheet, object: nil)
    }
    
    func showPasscodeView() {
        NotificationCenter.default.post(name: NSNotification.passcodeView, object: nil)
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
    static var passcodeView = Notification.Name.init("passcodeView")
    static var addTransactionView = Notification.Name.init("passcodeView")
    static var hideTabbar = Notification.Name.init("hideTabbar")
    static var showTabbar = Notification.Name.init("showTabbar")
    static var refresh = Notification.Name.init("refresh")
}
