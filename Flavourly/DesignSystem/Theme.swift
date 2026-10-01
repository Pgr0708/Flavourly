import SwiftUI

/// Flavourly design tokens. Values match the approved design canvas.
enum Theme {
    // MARK: Brand
    static let green = Color(hex: "#155634")
    static let greenLight = Color(hex: "#3A9A64")
    static let leaf = Color(hex: "#75B85B")
    static let greenSoft = Color(hex: "#E7F3E1")
    static let greenTint = Color(hex: "#F3F8EF")
    static let ink = Color(hex: "#172333")
    static let ink2 = Color(hex: "#4D5766")
    static let muted = Color(hex: "#6A7385")
    static let canvas = Color(hex: "#FAFBF9")
    static let cream = Color(hex: "#FFF9EB")
    static let line = Color(hex: "#E6E8E3")
    static let hairline = Color(hex: "#EFF1ED")
    static let chip = Color(hex: "#F0F1F2")

    // MARK: Meaning
    static let ai = Color(hex: "#974AE6")
    static let aiDeep = Color(hex: "#7137C2")
    static let aiSoft = Color(hex: "#F3ECFD")
    static let premium = Color(hex: "#E5A531")
    static let premiumDeep = Color(hex: "#6E4A00")
    static let premiumSoft = Color(hex: "#FFF2D7")
    static let allergen = Color(hex: "#C2362B")
    static let allergenSoft = Color(hex: "#FDECEA")
    static let check = Color(hex: "#8F4E00")
    static let checkSoft = Color(hex: "#FFF3DC")
    static let pantry = Color(hex: "#137A80")
    static let pantrySoft = Color(hex: "#E2F5F5")
    static let plan = Color(hex: "#BD3870")
    static let planSoft = Color(hex: "#FDEBF2")
    static let capture = Color(hex: "#A84D12")
    static let captureSoft = Color(hex: "#FFF1E4")
    static let star = Color(hex: "#E5A531")

    // MARK: Gradients
    static let greenGradient = LinearGradient(colors: [greenLight, green], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let flameGradient = LinearGradient(
        colors: [Color(hex: "#F2872E"), Color(hex: "#DE4A2C"), Color(hex: "#B8285E")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Darker flame used under white text (keeps 4.5:1 contrast).
    static let flameTextGradient = LinearGradient(colors: [Color(hex: "#C94F1E"), Color(hex: "#B02C58")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let aiGradient = LinearGradient(colors: [Color(hex: "#A965F0"), aiDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let premiumGradient = LinearGradient(colors: [Color(hex: "#FFE497"), Color(hex: "#FFB73E")], startPoint: .top, endPoint: .bottom)
    static let creamGradient = LinearGradient(colors: [Color(hex: "#F7FBF5"), Color(hex: "#FFFAEF")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let aiWash = LinearGradient(colors: [Color(hex: "#F1E8FD"), canvas], startPoint: .top, endPoint: .center)
    static let cookedWash = LinearGradient(colors: [Color(hex: "#EAF5E4"), canvas], startPoint: .top, endPoint: .center)

    // MARK: Type
    // Each family has one job, so screens feel varied but stay consistent. All ship with iOS
    // (Pacifico is bundled) and all scale with Dynamic Type.
    //   Didot ........ editorial page and recipe titles      New York ... sheet titles, cook-mode steps
    //   Avenir Next .. section headings, labels, chips       SF Pro ..... reading text and buttons
    //   SF Rounded ... numbers: timers, macros, stats        Noteworthy . your own notes
    //   Pacifico ..... brand moments (greeting, Cook Now, "Nice cooking!")
    enum Heading: String {
        case medium = "AvenirNext-Medium", demiBold = "AvenirNext-DemiBold", bold = "AvenirNext-Bold", heavy = "AvenirNext-Heavy"
    }

    static func display(_ size: CGFloat) -> Font { .custom("Didot-Bold", size: size, relativeTo: .largeTitle) }
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func heading(_ size: CGFloat, _ weight: Heading = .bold) -> Font { .custom(weight.rawValue, size: size, relativeTo: .headline) }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func hand(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size, relativeTo: .body) }
    static func brand(_ size: CGFloat) -> Font { .custom("Pacifico-Regular", size: size, relativeTo: .title) }

    static let pageTitle = display(34)
    static let sheetTitle = serif(24)
    static let section = heading(19)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let micro = Font.system(size: 12)
    static let label = heading(11, .demiBold)

    // MARK: Motion
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let gentle = Animation.easeInOut(duration: 0.25)
}

/// Palette used for household member avatars and collection colours.
enum Swatch {
    static let all = ["#155634", "#C7631F", "#BD3870", "#137A80", "#7137C2", "#B57F10", "#2E6FB7", "#8A4B2E"]
    static func color(for index: Int) -> String { all[abs(index) % all.count] }
}
