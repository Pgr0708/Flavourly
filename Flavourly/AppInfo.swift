//
//  AppInfo.swift
//  Flavourly
//
//  Created by Minaxi on 16/08/26.
//

import Foundation

enum AppInfo {
    static var appName: String = "Flavourly"
    
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.bhavik.Flavourly"
    }

    static var supportURLString: String =   "https://dakshyaminfotech.store/support/"
    static var termsURLString: String =     "https://dakshyaminfotech.store/terms-and-conditions/"
    static var privacyURLString: String =   "https://dakshyaminfotech.store/privacy-policy/"
    static var supportEmail: String =       "inovexa.contact@gmail.com"
}
