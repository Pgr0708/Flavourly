import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, cookbook, plan, shop

    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: "Home"
        case .cookbook: "Cookbook"
        case .plan: "Plan"
        case .shop: "Shop"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .cookbook: "book.closed"
        case .plan: "calendar"
        case .shop: "basket"
        }
    }
}

enum QuickAction: String, CaseIterable, Identifiable {
    case link, scan, write, grocery

    var id: String { rawValue }
    var title: String {
        switch self {
        case .link: "Paste a recipe link"
        case .scan: "Scan a recipe"
        case .write: "Write a recipe"
        case .grocery: "Add a grocery item"
        }
    }
    var symbol: String {
        switch self {
        case .link: "link"
        case .scan: "doc.text.viewfinder"
        case .write: "square.and.pencil"
        case .grocery: "basket.fill"
        }
    }
    var tint: Color {
        switch self {
        case .link: Theme.capture
        case .scan: Theme.pantry
        case .write: Theme.green
        case .grocery: Theme.aiDeep
        }
    }
}

/// Tab bar option B: floating dock + Cook Now flame.
struct KitchenDock: View {
    @Binding var selection: AppTab
    @Binding var quickAddOpen: Bool
    let onCook: () -> Void
    let onQuickAction: (QuickAction) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in tabButton(tab) }
            }
            .padding(.horizontal, 7)
            .frame(height: 66)
            .background {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(.white.opacity(0.72)))
                    .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.06)))
                    .shadow(color: Theme.ink.opacity(0.16), radius: 18, y: 10)
            }

            FlameButton(isOpen: quickAddOpen) {
                if quickAddOpen {
                    closeQuickAdd()
                } else {
                    Haptics.primary()
                    onCook()
                }
            } onLongPress: {
                openQuickAdd()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            guard selection != tab else { return }
            Haptics.select()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { selection = tab }
        } label: {
            HStack(spacing: 7) {
                // symbolVariant falls back to the outline when a symbol has no filled form (e.g. "calendar").
                Image(systemName: tab.symbol)
                    .symbolVariant(isOn ? .fill : .none)
                    .font(.system(size: 19, weight: isOn ? .bold : .medium))
                    .symbolEffect(.bounce, value: isOn)
                if isOn {
                    Text(LocalizedStringKey(tab.label))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundStyle(isOn ? .white : Theme.muted)
            .padding(.horizontal, isOn ? 15 : 0)
            .frame(minWidth: 46)
            .frame(height: 50)
            .background {
                if isOn {
                    Capsule()
                        .fill(Theme.greenGradient)
                        .shadow(color: Theme.green.opacity(0.32), radius: 8, y: 5)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func openQuickAdd() {
        Haptics.longPress()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { quickAddOpen = true }
        for index in QuickAction.allCases.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(index + 1)) { Haptics.impact(.light, intensity: 0.7) }
        }
    }

    private func closeQuickAdd() {
        Haptics.tick()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { quickAddOpen = false }
    }
}

/// Warm gradient orb. Tap = Cook Now, hold = quick add.
struct FlameButton: View {
    var isOpen: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.flameGradient)
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 3))
                .shadow(color: Color(hex: "#DE4A2C").opacity(glow ? 0.55 : 0.35), radius: glow ? 18 : 12, y: 8)
            if isOpen {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 25, weight: .bold))
                        .symbolEffect(.variableColor.iterative, options: .repeating.speed(0.35), isActive: !isOpen)
                    Text("COOK").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                }
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 70, height: 70)
        .scaleEffect(isOpen ? 1.08 : 1)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.35, perform: onLongPress)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement()
        .accessibilityLabel(isOpen ? "Close quick add" : "Cook now")
        .accessibilityHint("Double-tap and hold for quick add")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Quick add", onLongPress)
    }
}

/// Speed-dial shown while the flame is held.
struct QuickAddMenu: View {
    let onSelect: (QuickAction) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .transition(.opacity)
            VStack(alignment: .trailing, spacing: 10) {
                ForEach(Array(QuickAction.allCases.enumerated()), id: \.element) { index, action in
                    Button {
                        Haptics.success()
                        onSelect(action)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(action.tint)
                                .frame(width: 34, height: 34)
                                .background(action.tint.opacity(0.13), in: Circle())
                            Text(action.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 16)
                        .frame(height: 46)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity)
                            .animation(.spring(response: 0.38, dampingFraction: 0.7).delay(0.04 * Double(QuickAction.allCases.count - index))),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
                }
            }
            .padding(.trailing, 18)
            .padding(.bottom, 96)
        }
    }
}
