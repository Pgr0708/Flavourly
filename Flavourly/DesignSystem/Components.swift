import SwiftUI

// MARK: - Buttons

enum ButtonTone { case green, ai, flame, dark, outline, soft, premium, plain }

/// Scales slightly on press; every tap gets its own haptic via the action wrappers.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    @Environment(\.locale) private var locale
    var systemImage: String?
    var tone: ButtonTone = .green
    var isLoading = false
    var isEnabled = true
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isLoading else { return }
            tone == .outline || tone == .soft || tone == .plain ? Haptics.tick() : Haptics.primary()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(Lang.text(title, locale)).font(.system(size: height < 50 ? 15 : 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: height < 50 ? 14 : 16, style: .continuous))
            .overlay {
                if tone == .outline {
                    RoundedRectangle(cornerRadius: height < 50 ? 14 : 16, style: .continuous)
                        .strokeBorder(Theme.green.opacity(0.3), lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
    }

    private var foreground: Color {
        switch tone {
        case .outline, .soft: Theme.green
        case .premium: Color(hex: "#1E1B12")
        case .plain: Theme.ink2
        default: .white
        }
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .green: AnyShapeStyle(Theme.green)
        case .ai: AnyShapeStyle(Theme.aiGradient)
        case .flame: AnyShapeStyle(Theme.flameTextGradient)
        case .dark: AnyShapeStyle(Theme.ink)
        case .outline: AnyShapeStyle(Color.white)
        case .soft: AnyShapeStyle(Theme.greenSoft)
        case .premium: AnyShapeStyle(Theme.premiumGradient)
        case .plain: AnyShapeStyle(Color.clear)
        }
    }
}

/// Round 44pt icon button used in nav bars.
struct IconButton: View {
    let systemImage: String
    let label: String
    @Environment(\.locale) private var locale
    var style: Style = .plain
    var tint: Color = Theme.ink
    let action: () -> Void

    enum Style { case plain, bordered, dark, glass }

    var body: some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(style == .dark || style == .glass ? .white : tint)
                .frame(width: 44, height: 44)
                .background {
                    switch style {
                    case .plain: Color.clear
                    case .bordered: Circle().fill(.white).overlay(Circle().strokeBorder(Theme.line))
                    case .dark: Circle().fill(.black.opacity(0.42))
                    case .glass: Circle().fill(.white.opacity(0.16)).overlay(Circle().strokeBorder(.white.opacity(0.2)))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Lang.text(label, locale))
    }
}

// MARK: - Chips & badges

struct Chip: View {
    let title: String
    @Environment(\.locale) private var locale
    var systemImage: String?
    var isOn = false
    var style: Style = .ink
    var small = false
    let action: () -> Void

    enum Style { case ink, green, red, ai, outline, dashed }

    var body: some View {
        Button {
            Haptics.toggle()
            withAnimation(Theme.snappy) { action() }
        } label: {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: small ? 11 : 12, weight: .bold)) }
                else if isOn, style != .ink { Image(systemName: "checkmark").font(.system(size: small ? 10 : 11, weight: .heavy)) }
                Text(Lang.text(title, locale)).font(Theme.heading(small ? 12 : 13, .demiBold)).lineLimit(1)
            }
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? 30 : 36)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay { Capsule().strokeBorder(border, style: StrokeStyle(lineWidth: isOn && style != .ink ? 1.5 : 1, dash: style == .dashed ? [4, 3] : [])) }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var foreground: Color {
        guard isOn else { return style == .dashed ? Theme.ink2 : Theme.ink }
        switch style {
        case .ink: return .white
        case .green, .outline: return Theme.green
        case .red: return Theme.allergen
        case .ai: return Theme.aiDeep
        case .dashed: return Theme.ink2
        }
    }

    private var background: Color {
        guard isOn else { return style == .outline ? .white : (style == .dashed ? .clear : Theme.chip) }
        switch style {
        case .ink: return Theme.ink
        case .green, .outline: return Theme.greenSoft
        case .red: return Theme.allergenSoft
        case .ai: return Theme.aiSoft
        case .dashed: return .clear
        }
    }

    private var border: Color {
        if style == .dashed { return Color(hex: "#CDD2CA") }
        guard isOn else { return style == .outline ? Theme.line : .clear }
        switch style {
        case .green, .outline: return Theme.green.opacity(0.45)
        case .red: return Theme.allergen.opacity(0.35)
        case .ai: return Theme.ai.opacity(0.4)
        default: return .clear
        }
    }
}

enum BadgeTone { case green, red, amber, purple, teal, neutral, gold, pink, white, orange }

struct Badge: View {
    let text: String
    @Environment(\.locale) private var locale
    var systemImage: String?
    var tone: BadgeTone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(Lang.text(text, locale)).font(Theme.heading(11, .demiBold)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .foregroundStyle(colors.0)
        .background(colors.1, in: Capsule())
    }

    private var colors: (Color, Color) {
        switch tone {
        case .green: (Theme.green, Theme.greenSoft)
        case .red: (Theme.allergen, Theme.allergenSoft)
        case .amber: (Theme.check, Theme.checkSoft)
        case .purple: (Theme.aiDeep, Theme.aiSoft)
        case .teal: (Theme.pantry, Theme.pantrySoft)
        case .neutral: (Theme.ink2, Theme.chip)
        case .gold: (Theme.premiumDeep, Theme.premiumSoft)
        case .pink: (Theme.plan, Theme.planSoft)
        case .white: (Theme.ink, Color.white.opacity(0.94))
        case .orange: (Theme.capture, Theme.captureSoft)
        }
    }
}

// MARK: - Layout

/// Wraps chips onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // 1 pt tolerance: the parent may round our frame a hair narrower than the width we reported,
            // which would otherwise push the last chip onto an unmeasured line (overlapping what follows).
            if x > 0, x + size.width > width + 1 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX + 1 {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct SectionHeader: View {
    let title: String
    @Environment(\.locale) private var locale
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Lang.text(title, locale)).font(Theme.heading(19)).foregroundStyle(Theme.ink)
                if let subtitle { Text(Lang.text(subtitle, locale)).font(Theme.micro).foregroundStyle(Theme.muted) }
            }
            Spacer()
            if let actionTitle, let action {
                Button(Lang.text(actionTitle, locale)) {
                    Haptics.tick()
                    action()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.green)
            }
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 18
    var bordered = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if bordered { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line) }
            }
            .shadow(color: bordered ? .clear : Theme.ink.opacity(0.05), radius: 12, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 18, bordered: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, bordered: bordered))
    }

    /// Standard screen background.
    func canvasBackground() -> some View {
        background(Theme.canvas.ignoresSafeArea())
    }
}

// MARK: - Controls

struct StepperPill: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...24
    var label = "servings"

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(Theme.rounded(17))
                .monospacedDigit()
                .frame(minWidth: 28)
                .contentTransition(.numericText(value: Double(value)))
            button("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .frame(height: 44)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, change: @escaping () -> Void) -> some View {
        Button {
            Haptics.step()
            withAnimation(Theme.snappy) { change() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? Theme.green : Theme.muted.opacity(0.4))
                .frame(width: 42, height: 42)
        }
        .disabled(!enabled)
    }
}

struct CheckCircle: View {
    var isOn: Bool
    var tint: Color = Theme.green

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? tint : Color(hex: "#C3C8CE"), lineWidth: 2)
                .background(Circle().fill(isOn ? tint : .white))
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
        .animation(Theme.snappy, value: isOn)
    }
}

struct ToggleRow: View {
    let title: String
    @Environment(\.locale) private var locale
    var subtitle: String?
    var systemImage: String?
    var tint: Color = Theme.green
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            Haptics.toggle()
            isOn = value
        })) {
            HStack(spacing: 12) {
                if let systemImage {
                    IconTile(systemImage: systemImage, tint: tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Lang.text(title, locale)).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    if let subtitle { Text(Lang.text(subtitle, locale)).font(Theme.micro).foregroundStyle(Theme.muted) }
                }
            }
        }
        .tint(tint == Theme.ai ? Theme.ai : Theme.green)
        .frame(minHeight: 54)
    }
}

struct IconTile: View {
    let systemImage: String
    var tint: Color = Theme.green
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Media

/// The small "Photo by … on Pexels" tag photo licences ask for; opens the photographer's page when there is one.
struct CreditLabel: View {
    let credit: ImageCredit

    var body: some View {
        // Photographer credits stay as written; only our own "AI-generated image" is translated.
        let label = (credit.text == "AI-generated image" ? Text("AI-generated image") : Text(verbatim: credit.text))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(10)
        if let url = credit.link {
            Link(destination: url) { label }.accessibilityHint("Opens the photo's source")
        } else {
            label
        }
    }
}

/// Small source images get a blurred backdrop instead of being stretched.
/// Recipe photo: stored photo → bundled image → web thumbnail → illustrated fallback.
struct RecipeImage: View {
    let recipe: Recipe?
    var cornerRadius: CGFloat = 16
    var isHero = false
    @ObservedObject private var fills = PhotoFill.shared

    var body: some View {
        GeometryReader { geometry in
            content(size: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: recipe?.key) { if let recipe { PhotoFill.shared.request(recipe) } }
        .overlay(alignment: .bottomTrailing) {
            // Only for web photos actually shown, above the rounded content card that overlaps the hero.
            if isHero, recipe?.imageData == nil, recipe?.imageName == nil, let credit = ImageCredit(recipe?.imageURL) {
                CreditLabel(credit: credit).padding(.bottom, 30)
            }
        }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let data = recipe?.imageData, let image = UIImage(data: data) {
            fitted(Image(uiImage: image), pixelWidth: image.size.width * image.scale, size: size)
        } else if let name = recipe?.imageName, let image = UIImage(named: name) {
            fitted(Image(uiImage: image), pixelWidth: image.size.width * image.scale, size: size)
        } else if let link = recipe?.imageURL, let url = URL(string: link) {
            RemoteImage(url: url) {
                RecipeArt(title: recipe?.displayTitle ?? "", cuisine: recipe?.cuisine).shimmering()
            } failure: {
                RecipeArt(title: recipe?.displayTitle ?? "", cuisine: recipe?.cuisine)
            }
        } else {
            RecipeArt(title: recipe?.displayTitle ?? "", cuisine: recipe?.cuisine)
        }
    }

    /// Every photo fills its frame edge to edge (no small centred copy on a blurred background).
    private func fitted(_ image: Image, pixelWidth: CGFloat, size: CGSize) -> some View {
        image.resizable().scaledToFill()
    }
}

/// Illustrated cover for recipes without a photo: warm gradient + dish emoji.
struct RecipeArt: View {
    let title: String
    var cuisine: String?

    var body: some View {
        let palette = colors
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.18)).scaleEffect(0.9).offset(x: side * 0.25, y: -side * 0.2)
                // Sized to the card, not a fixed 54 pt that left a big card mostly empty.
                Text(emoji).font(.system(size: max(40, side * 0.42))).shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var emoji: String {
        let text = title.lowercased()
        let table: [(String, String)] = [
            ("curry", "🍛"), ("masala", "🍛"), ("paneer", "🍛"), ("dal", "🥣"), ("soup", "🥣"), ("oats", "🥣"), ("porridge", "🥣"),
            ("poha", "🍚"), ("rice", "🍚"), ("biryani", "🍚"), ("cheela", "🥞"), ("pancake", "🥞"), ("dosa", "🥞"),
            ("wrap", "🌯"), ("taco", "🌮"), ("salad", "🥗"), ("bowl", "🥗"), ("parfait", "🍨"), ("yoghurt", "🍨"),
            ("makhana", "🍿"), ("hummus", "🫘"), ("chana", "🫘"), ("shakshuka", "🍳"), ("egg", "🍳"), ("pasta", "🍝"),
            ("noodle", "🍜"), ("pizza", "🍕"), ("burger", "🍔"), ("sandwich", "🥪"), ("cake", "🍰"), ("cookie", "🍪"),
            ("smoothie", "🥤"), ("fish", "🐟"), ("salmon", "🐟"), ("chicken", "🍗"), ("steak", "🥩"), ("bread", "🍞")
        ]
        return table.first { text.contains($0.0) }?.1 ?? "🍽️"
    }

    private var colors: [Color] {
        switch (cuisine ?? "").lowercased() {
        case "indian": [Color(hex: "#FFB861"), Color(hex: "#E2632B")]
        case "italian": [Color(hex: "#F6A38B"), Color(hex: "#C8463A")]
        case "mediterranean", "middle eastern": [Color(hex: "#A8D5A0"), Color(hex: "#2E8B57")]
        case "chinese", "japanese", "thai", "korean": [Color(hex: "#FFC98B"), Color(hex: "#D9822B")]
        default: [Color(hex: "#F3D9A4"), Color(hex: "#D39B4A")]
        }
    }
}

/// Picture for a grocery / pantry item: real photo when we ship one, emoji otherwise.
struct IngredientIcon: View {
    let name: String
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let asset = IngredientArt.assetName(for: name), let image = UIImage(named: asset) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(IngredientArt.emoji(for: name))
                    .font(.system(size: size * 0.55))
                    .frame(width: size, height: size)
                    .background(Theme.cream)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.hairline))
        .accessibilityHidden(true)
    }
}

struct Avatar: View {
    let initial: String
    let color: Color
    var size: CGFloat = 36
    var ringed = false

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay {
                if ringed { Circle().strokeBorder(.white, lineWidth: 2) }
            }
    }
}

// MARK: - States

struct EmptyStateView: View {
    var imageName: String? = "HomeEmptyPot"
    var systemImage: String?
    let title: String
    @Environment(\.locale) private var locale
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .frame(width: 76, height: 76)
                    .background(Theme.greenSoft, in: Circle())
                    .symbolEffect(.bounce, options: .nonRepeating)
            } else if let imageName {
                Image(imageName).resizable().scaledToFit().frame(height: 110).accessibilityHidden(true)
            }
            Text(Lang.text(title, locale)).font(Theme.serif(19)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(Lang.text(message, locale)).font(Theme.caption).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, tone: .soft, height: 44, action: action)
                    .frame(maxWidth: 240)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Soft moving highlight for loading placeholders.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: phase * geometry.size.width * 1.4)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Celebration burst for finished cooks and completed lists.
struct ConfettiView: View {
    @State private var start = Date.now
    private let colors: [Color] = [Theme.leaf, Theme.plan, Color(hex: "#FFB73E"), Theme.ai, Color(hex: "#24ADB5")]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed < 2.6 else { return }
                for index in 0..<46 {
                    let seed = Double(index) * 12.9898
                    let angle = (seed.truncatingRemainder(dividingBy: 6.28)) - 3.14
                    let speed = 180 + (seed.truncatingRemainder(dividingBy: 140))
                    let x = size.width / 2 + cos(angle) * speed * elapsed
                    let y = size.height * 0.35 + sin(angle) * speed * elapsed * 0.6 + 260 * elapsed * elapsed
                    let rect = CGRect(x: x, y: y, width: 7, height: index.isMultiple(of: 2) ? 7 : 12)
                    context.opacity = max(0, 1 - elapsed / 2.6)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[index % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Sheet header with title and close button.
struct SheetHeader: View {
    let title: String
    @Environment(\.locale) private var locale
    var subtitle: String?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Lang.text(title, locale)).font(Theme.sheetTitle).foregroundStyle(Theme.ink)
                if let subtitle { Text(Lang.text(subtitle, locale)).font(Theme.micro).foregroundStyle(Theme.muted) }
            }
            Spacer()
            if let onClose {
                IconButton(systemImage: "xmark", label: "Close", action: onClose)
                    .padding(.trailing, -10)
                    .padding(.top, -6)
            }
        }
    }
}

/// "1 serving", "3 servings" — English plurals for counts shown in the UI.
func plural(_ count: Int, _ word: String) -> String {
    "\(count.formatted()) \(word)\(count == 1 ? "" : "s")"
}

/// Minutes → "1 hr 15 min".
func durationText(_ minutes: Int) -> String {
    guard minutes > 0 else { return "—" }
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60, rest = minutes % 60
    return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
}

/// Inline validation message under a field — tells the user exactly what to fix.
struct FieldError: View {
    let message: String?
    @Environment(\.locale) private var locale

    var body: some View {
        if let message {
            Label(Lang.text(message, locale), systemImage: "exclamationmark.circle.fill")
                .font(Theme.micro.weight(.medium))
                .foregroundStyle(Theme.allergen)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Problem: \(message)")
        }
    }
}

/// "123 / 2,000" counter that turns red when over the limit.
struct CharacterCount: View {
    let count: Int
    let limit: Int

    var body: some View {
        Text("\(count.formatted()) / \(limit.formatted())")
            .font(Theme.rounded(11, .medium).monospacedDigit())
            .foregroundStyle(count > limit ? Theme.allergen : Theme.muted)
    }
}
