//
//  AppDelegate.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import Foundation
import Firebase
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import RevenueCat
import CoreData

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        
        if hasRevenueCatAPIKey {
            Purchases.logLevel = .debug
            Purchases.configure(withAPIKey: revenueCatAPIKey)
            Purchases.shared.delegate = self
            Purchases.shared.getCustomerInfo { customerInfo, _ in
                guard let customerInfo else { return }
                BaseViewModel().checkUserIsPro(customerInfo: customerInfo)
            }
        }
        
        // The FCM token arrives in messaging(_:didReceiveRegistrationToken:) once APNs has a token —
        // asking for it here, before APNs, always fails with error 505.
        Messaging.messaging().delegate = self
        application.registerForRemoteNotifications()
        
        return true
    }
    
    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Oh no! Failed to register for remote notifications with error \(error)")
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        var readableToken = ""
        for index in 0 ..< deviceToken.count {
            readableToken += String(format: "%02.2hhx", deviceToken[index] as CVarArg)
        }
        print("Received an APNs device token: \(readableToken)")
        Messaging.messaging().apnsToken = deviceToken
    }
}

extension AppDelegate: MessagingDelegate {
    @objc func messaging(_: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase token: \(String(describing: fcmToken))")
    }
}

extension AppDelegate : PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        BaseViewModel().checkUserIsPro(customerInfo: customerInfo)
    }
}
