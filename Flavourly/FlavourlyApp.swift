//
//  FlavourlyApp.swift
//  Flavourly
//
//  Created by Minaxi on 30/09/26.
//

import SwiftUI
import CoreData

@main
struct FlavourlyApp: App {
    @StateObject private var settings = SettingsManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // Recipe photos and API responses survive relaunches; ImageLoader reads through this.
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
    }
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(settings)
                .environment(
                    \.locale,
                     Locale(identifier: settings.languageCode)
                     )
                .environment(
                           \.managedObjectContext,
                           CoreDataManager.shared.context
                       )
                .preferredColorScheme(settings.preferredColorScheme)
        }
    }
}
