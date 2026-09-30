//
//  Languages.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI

enum Languages: String, CaseIterable, Identifiable {
    case english = "English"
    case arabic = "Arabic"
    case german = "German"
    case hindi = "Hindi"
    case spanish = "Spanish"
    case french = "French"
    case japanese = "Japanese"
    case chinese = "Chinese"
    case greek = "Greek"
    case italian = "Italian"
    case korean = "Korean"
    case portuguese = "Portuguese"
    case russian = "Russian"
    case turkish = "Turkish"
    case vietnamese = "Vietnamese"

    var id: Self { self }

    var shortCode: String {
        switch self {
        case .english: return "EN"
        case .arabic: return "AR"
        case .german: return "DE"
        case .hindi: return "HI"
        case .spanish: return "ES"
        case .french: return "FR"
        case .japanese: return "JA"
        case .chinese: return "ZH"
        case .greek: return "EL"
        case .italian: return "IT"
        case .korean: return "KO"
        case .portuguese: return "PT"
        case .russian: return "RU"
        case .turkish: return "TR"
        case .vietnamese: return "VI"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .arabic: return "🇦🇪"
        case .german: return "🇩🇪"
        case .hindi: return "🇮🇳"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .japanese: return "🇯🇵"
        case .chinese: return "🇨🇳"
        case .greek: return "🇬🇷"
        case .italian: return "🇮🇹"
        case .korean: return "🇰🇷"
        case .portuguese: return "🇵🇹"
        case .russian: return "🇷🇺"
        case .turkish: return "🇹🇷"
        case .vietnamese: return "🇻🇳"
        }
    }

    var localizedName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية"
        case .german: return "Deutsch"
        case .hindi: return "हिन्दी"
        case .spanish: return "Español"
        case .french: return "Français"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        case .greek: return "Ελληνικά"
        case .italian: return "Italiano"
        case .korean: return "한국어"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .turkish: return "Türkçe"
        case .vietnamese: return "Tiếng Việt"
        }
    }
}
