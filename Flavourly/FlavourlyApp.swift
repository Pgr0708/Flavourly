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
        // API responses survive relaunches; recipe photos use Kingfisher's own memory + disk cache.
        URLCache.shared = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        ImageCaching.configure()
    }
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(settings)
                .environment(
                    \.locale,
                     Locale(identifier: Lang.lproj(for: settings.languageCode))
                     )
                .environment(
                           \.managedObjectContext,
                           CoreDataManager.shared.context
                       )
                .preferredColorScheme(settings.preferredColorScheme)
        }
    }
}
