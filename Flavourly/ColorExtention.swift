//
//  colorExtention.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import SwiftUI

extension Color {
    init(hex: String) {
            let hex = hex.replacingOccurrences(of: "#", with: "")
            let value = Int(hex, radix: 16) ?? 0

            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    
    static let backgroundLinearGradient = LinearGradient(stops: [
        .init(color: Color(hex: "#12B3B0"), location: 0.0),
        .init(color: Color(hex: "#0A9396"), location: 0.48),
        .init(color: Color(hex: "#065C60"), location: 1.0)
    ], startPoint: .topTrailing, endPoint: .bottomLeading)
    
    static func backgroundDynamicLinearGradient(
        color1: Color,
        color2: Color,
        color3: Color
    ) -> LinearGradient {

        LinearGradient(
            stops: [
                .init(color: color1, location: 0.0),
                .init(color: color2, location: 0.48),
                .init(color: color3, location: 1.0)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }
    
    // MARK: Brand
    static var primaryColor: Color {
        let accentName = UserDefaults.standard.string(forKey: "selectedAccentColor") ?? "Teal"
        switch accentName {
        case "Teal": return Color(hex: "#0A9396")
        case "Ocean": return Color(hex: "#0066FF")
        case "Purple": return Color(hex: "#8A2BE2")
        case "Amber": return Color(hex: "#FFBF00")
        case "Emerald": return Color(hex: "#00A86B")
        default: return Color(hex: "#0A9396")
        }
    }
    
    static var primaryInkColor: Color {
        primaryColor.opacity(0.85)
    }
    
    static var primarySoftColor: Color {
        primaryColor.opacity(0.12)
    }
    
    // MARK: SurfacesColor
    static let backgroundColor  = Color("Background")
    static let surfaceColor  = Color("Surface")
    static let surface2Color  = Color("Surface2")
    
    // MARK: TextColor
    static let textColor  = Color("Text")
    static let text2Color  = Color("Text2")
    static let text3Color  = Color("Text3")
    static let dividerColor  = Color("Divider")
    
    // MARK: StatusColor
    static let successColor  = Color("Success")
    static let warningColor  = Color("Warning")
    static let dangerColor  = Color("Danger")

    // MARK: Category accents
    static let productivityColor  = Color("CategoryProductivity")
    static let fitnessColor       = Color("CategoryFitness")
    static let entertainmentColor = Color("CategoryEntertainment")
    static let musicColor         = Color("CategoryMusic")
    static let educationColor     = Color("CategoryEducation")
    static let newsColor          = Color("CategoryNews")
    static let cloudStorageColor  = Color("CategoryCloudStorage")
    
    static let goldAccentColor  = Color("GoldAccent")
    
    static let selectedLanguageBackground = Color(hex: "#E1F0F0")
    static let textOnBrandColor   = Color("TextOnBrand")
}
