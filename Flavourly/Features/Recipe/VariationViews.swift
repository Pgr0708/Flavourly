import SwiftUI

/// Premium "make it my way": the cook describes a change, the server rewrites the whole recipe once,
/// saves it and shows it to other cooks in the same country (same region first).
@MainActor
enum Variations {
    struct Item: Decodable, Identifiable {
        let id: String
        let title: String
        let change: String
        let baseTitle: String
        let country: String?
        let region: String?
        let tried: Int
        let recipe: RecipeDraft
    }

    static func make(from recipe: Recipe, change: String) async throws -> Item {
        struct Base: Encodable {
            let title: String
            let servings: Int
            let ingredients: [String]
            let steps: [String]
            let imageURL: String?
        }
        struct Body: Encodable { let base: Base; let change: String; let country: String; let region: String? }
        struct Reply: Decodable { let variation: Item }
        let lines = recipe.sortedIngredients.map(\.checkLine).filter { !$0.isEmpty }
        let base = Base(
            title: String(recipe.displayTitle.prefix(120)),
            servings: min(100, max(1, Int(recipe.servings))),
            ingredients: Array(lines.prefix(80).map { String($0.prefix(200)) }),
            steps: Array(recipe.stepTexts.filter { !$0.isEmpty }.prefix(60).map { String($0.prefix(1_000)) }),
            imageURL: recipe.imageURL.flatMap { $0.hasPrefix("https://") ? String($0.prefix(600)) : nil }
        )
        let local = LocalFood.shared
        let item = try await APIClient.shared.post(Apis.variations, Body(base: base, change: String(change.prefix(200)), country: local.country, region: local.region),
                                                   as: Reply.self).variation
        Usage.record(.variation)
        cache.removeValue(forKey: recipe.displayTitle.lowercased())
        return item
    }

    private static var cache: [String: (at: Date, items: [Item])] = [:]

    /// Versions of this dish made by cooks in the same country (kept for a few minutes).
    static func nearby(title: String) async -> [Item] {
        let key = title.lowercased()
        if let hit = cache[key], Date.now.timeIntervalSince(hit.at) < 300 { return hit.items }
        struct Body: Encodable { let title: String; let country: String; let region: String? }
        struct Reply: Decodable { let variations: [Item] }
        let local = LocalFood.shared
        guard let reply = try? await APIClient.shared.post(Apis.variationsNearby, Body(title: String(title.prefix(120)), country: local.country, region: local.region),
                                                           as: Reply.self) else { return cache[key]?.items ?? [] }
        cache[key] = (.now, reply.variations)
        return reply.variations
    }

    static func tried(_ id: String) async {
        struct Body: Encodable { let id: String }
        struct Reply: Decodable { let tried: Int }
        _ = try? await APIClient.shared.post(Apis.variationTried, Body(id: id), as: Reply.self)
    }
}

// MARK: - The button on a recipe

struct MakeItMyWayButton: View {
    let recipe: Recipe
    let onCreated: (Route) -> Void
    @EnvironmentObject private var settings: SettingsManager
    @State private var showSheet = false

    var body: some View {
        Button {
            Haptics.primary()
            if settings.isPremium { showSheet = true } else { Paywall.show() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.ai, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Make it my way").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        if !settings.isPremium { Badge(text: "Premium", systemImage: "crown.fill", tone: .gold) }
                    }
                    Text("Add paneer, air fryer, vegan, less spicy — get a whole new recipe")
                        .font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(Theme.aiWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .sheet(isPresented: $showSheet) {
            MakeItMyWaySheet(recipe: recipe) { route in
                showSheet = false
                onCreated(route)
            }
            .environmentObject(settings)
        }
    }
}

private struct MakeItMyWaySheet: View {
    let recipe: Recipe
    let onCreated: (Route) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var change = ""
    @State private var working = false
    @FocusState private var typing: Bool

    private static let ideas = ["Healthier", "Vegan", "High protein", "Less oil", "Spicier", "Air fryer",
                                "No onion & garlic", "Kid-friendly", "Add paneer", "Gluten-free"]
    private var trimmed: String { change.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tell us what to change in \u{201C}\(recipe.displayTitle)\u{201D}. We'll rewrite every ingredient and step.")
                        .font(Theme.body).foregroundStyle(Theme.ink2)
                    TextField("e.g. add paneer, bake instead of fry, less spicy", text: $change, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($typing)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
                        .onChange(of: change) { _, value in if value.count > 200 { change = String(value.prefix(200)) } }
                    FlowChips(items: Self.ideas) { idea in
                        Haptics.select()
                        change = trimmed.isEmpty ? idea.lowercased() : "\(trimmed), \(idea.lowercased())"
                    }
                    Label("Your version is shared with cooks near you — never your name.", systemImage: "person.2.fill")
                        .font(Theme.micro).foregroundStyle(Theme.muted)
                    PrimaryButton(title: "Create my version", systemImage: "wand.and.stars", tone: .ai, isLoading: working,
                                  isEnabled: trimmed.count >= 3 && Usage.canUse(.variation)) { create() }
                    Text(Usage.canUse(.variation)
                         ? "\(Usage.remaining(.variation)) new versions left this week"
                         : "You've made this week's versions. More on \(Usage.resetDate.formatted(.dateTime.weekday(.wide))).")
                        .font(Theme.micro).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .canvasBackground()
            .navigationTitle("Make it my way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { typing = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        typing = false
        working = true
        Task {
            defer { working = false }
            do {
                let item = try await Variations.make(from: recipe, change: trimmed)
                guard let made = Library.shared.add([item.recipe]).first else { throw APIError.invalidResponse }
                Haptics.success()
                DropsManager.showSuccess(title: "Your version is ready", subtitle: item.title)
                onCreated(made.route)
            } catch APIError.limit(let message) {
                Usage.exhaust(.variation)
                DropsManager.showWarning(title: "Weekly limit reached", subtitle: message)
            } catch APIError.premiumRequired {
                dismiss()
                Paywall.show()
            } catch {
                Haptics.error()
                DropsManager.showError(title: "Couldn't make that version", subtitle: error.localizedDescription)
            }
        }
    }
}

/// One swipeable row of idea chips.
private struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) { chips }.scrollIndicators(.hidden)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { tap(item) } label: {
                    Text(LocalizedStringKey(item)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.chip, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Made by people near you

/// At the bottom of a recipe: other cooks' own versions of this dish, from the same region first.
struct NearbyVersionsSection: View {
    let title: String
    let onOpen: (Route) -> Void
    @ObservedObject private var local = LocalFood.shared
    @State private var items: [Variations.Item] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Made by people near you", systemImage: "person.2.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("Their own twist on this dish · \(local.placeName)").font(Theme.micro).foregroundStyle(Theme.muted)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            Button { open(item) } label: { card(item) }.buttonStyle(PressableStyle(scale: 0.97))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: "\(title)|\(local.country)|\(local.region ?? "")") { items = await Variations.nearby(title: title) }
    }

    private func card(_ item: Variations.Item) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            DishPhoto(url: item.recipe.imageURL, title: item.title).frame(width: 200, height: 120).clipped()
            Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).padding(.horizontal, 10)
            Text("\u{201C}\(item.change)\u{201D}\(item.region.map { " · \($0)" } ?? "")")
                .font(Theme.micro).foregroundStyle(Theme.ai).lineLimit(1).padding(.horizontal, 10)
            if item.tried > 0 {
                Label("\(item.tried) cooked it", systemImage: "flame.fill").font(Theme.micro).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
            }
        }
        .frame(width: 200, alignment: .leading)
        .padding(.bottom, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func open(_ item: Variations.Item) {
        Haptics.select()
        if let recipe = Library.shared.add([item.recipe]).first { onOpen(recipe.route) }
    }
}
