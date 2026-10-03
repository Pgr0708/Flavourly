import SwiftUI

// MARK: - Entry row (Home and Cookbook › Discover)

/// "Explore world kitchens": famous dishes from other countries; opens each country's kitchen.
struct WorldKitchensRow: View {
    @ObservedObject private var local = LocalFood.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore world kitchens").font(Theme.section).foregroundStyle(Theme.ink)
                    Text("Famous home cooking from every country").font(Theme.micro).foregroundStyle(Theme.muted)
                }
                Spacer()
                NavigationLink(value: Route.worldKitchens) { Text("See all") }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(Theme.green)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(WorldKitchens.featured.filter { $0.country != local.country }, id: \.country) { item in
                        NavigationLink(value: Route.country(item.country)) {
                            KitchenCard(code: item.country, dish: item.dish).frame(width: 150, height: 190)
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// A country as a photo of its most famous dish, with its flag and name.
struct KitchenCard: View {
    let code: String
    let dish: String
    @State private var photo: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DishPhoto(url: photo, title: dish)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(LocalFood.flag(for: code)) \(LocalFood.name(for: code))")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(dish).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .task { photo = await WorldKitchens.photo(of: dish) }
    }
}

/// A web photo that fills its frame, with the illustrated placeholder while it loads or if none exists.
struct DishPhoto: View {
    let url: String?
    let title: String

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let url, let link = URL(string: url) {
                    RemoteImage(url: link) { RecipeArt(title: title).shimmering() } failure: { RecipeArt(title: title) }
                } else {
                    RecipeArt(title: title)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

// MARK: - All countries

struct WorldKitchensView: View {
    @State private var query = ""

    private var matches: [String] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return LocalFood.countries }
        return LocalFood.countries.filter { LocalFood.name(for: $0).localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if query.isEmpty {
                    Text("Popular kitchens").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(WorldKitchens.featured, id: \.country) { item in
                            NavigationLink(value: Route.country(item.country)) {
                                KitchenCard(code: item.country, dish: item.dish).frame(height: 180)
                            }
                            .buttonStyle(PressableStyle(scale: 0.97))
                        }
                    }
                    Text("Every country").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 6)
                }
                LazyVStack(spacing: 0) {
                    ForEach(matches, id: \.self) { code in
                        NavigationLink(value: Route.country(code)) {
                            HStack(spacing: 12) {
                                Text(LocalFood.flag(for: code)).font(.system(size: 26))
                                Text(LocalFood.name(for: code)).font(.system(size: 16)).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
                    }
                }
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("World kitchens")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One country

struct CountryKitchenView: View {
    let code: String
    @State private var regions: [WorldKitchens.Region] = []
    @State private var dishes: [Recipe] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(LocalFood.flag(for: code)) \(LocalFood.name(for: code))").font(Theme.display(30)).foregroundStyle(Theme.ink)
                    Text("Home cooking from every region").font(Theme.caption).foregroundStyle(Theme.muted)
                }
                if !regions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Famous regional kitchens").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(regions) { region in
                                    NavigationLink(value: Route.region(code, region.name)) { RegionCard(region: region) }
                                        .buttonStyle(PressableStyle(scale: 0.97))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                DishGrid(title: "Popular across \(LocalFood.name(for: code))", dishes: dishes, loading: loading, problem: problem) {
                    Task { await load() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(refreshingPhotos: true) }
    }

    private func load(refreshingPhotos: Bool = false) async {
        loading = true
        problem = nil
        async let regionList = try? WorldKitchens.regions(for: code)
        do {
            dishes = try await WorldKitchens.dishes(country: code, region: nil)
        } catch APIError.premiumRequired {
            problem = WorldKitchens.premiumNote
        } catch {
            problem = error.localizedDescription
        }
        regions = await regionList?.regions ?? regions
        loading = false
        if refreshingPhotos { await refreshPhotos() }
    }

    /// The server finds photos in the background; look again a few times while the page is open.
    private func refreshPhotos() async {
        for _ in 0..<4 where dishes.contains(where: { $0.imageURL == nil && $0.imageName == nil }) {
            try? await Task.sleep(for: .seconds(30))
            if let fresh = try? await WorldKitchens.dishes(country: code, region: nil) { dishes = fresh }
        }
    }
}

private struct RegionCard: View {
    let region: WorldKitchens.Region
    @State private var photo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DishPhoto(url: photo ?? region.imageURL, title: region.signature)
                .frame(width: 180, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(region.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text(region.about).font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 180, alignment: .leading)
        .task { if region.imageURL == nil, !region.signature.isEmpty { photo = await WorldKitchens.photo(of: region.signature) } }
    }
}

// MARK: - One region

struct RegionKitchenView: View {
    let code: String
    let region: String
    @State private var dishes: [Recipe] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(region).font(Theme.display(30)).foregroundStyle(Theme.ink)
                    Text("\(LocalFood.flag(for: code)) \(LocalFood.name(for: code)) · home cooking").font(Theme.caption).foregroundStyle(Theme.muted)
                }
                DishGrid(title: "Favourite dishes", dishes: dishes, loading: loading, problem: problem) {
                    Task { await load() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            for _ in 0..<4 where dishes.contains(where: { $0.imageURL == nil }) {
                try? await Task.sleep(for: .seconds(30))
                if let fresh = try? await WorldKitchens.dishes(country: code, region: region) { dishes = fresh }
            }
        }
    }

    private func load() async {
        loading = true
        problem = nil
        do {
            dishes = try await WorldKitchens.dishes(country: code, region: region)
        } catch APIError.premiumRequired {
            problem = WorldKitchens.premiumNote
        } catch {
            problem = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Shared grid

/// Two-column photo grid of dishes that fit everyone's food rules.
private struct DishGrid: View {
    let title: String
    let dishes: [Recipe]
    let loading: Bool
    let problem: String?
    let retry: () -> Void

    var body: some View {
        let profile = People.profile()
        let safe = dishes.filter { LocalFood.fits($0, profile) }
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            if let problem, dishes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey(problem)).font(Theme.caption).foregroundStyle(Theme.ink2)
                    if problem == WorldKitchens.premiumNote {
                        PrimaryButton(title: "Unlock with Premium", systemImage: "crown.fill", tone: .premium, height: 44) { Paywall.show() }
                    } else {
                        Button("Try again", action: retry).font(.system(size: 14, weight: .semibold)).tint(Theme.green)
                    }
                }
                .card(padding: 14)
            } else if loading, dishes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Finding favourite home dishes…").font(Theme.caption).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.chip).aspectRatio(0.8, contentMode: .fit).shimmering()
                        }
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(safe) { recipe in
                        NavigationLink(value: recipe.route) { DishTile(recipe: recipe) }
                            .buttonStyle(PressableStyle(scale: 0.97))
                    }
                }
                if safe.count < dishes.count {
                    Label("\(dishes.count - safe.count) hidden — not safe for your household", systemImage: "eye.slash")
                        .font(Theme.micro).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }
}

private struct DishTile: View {
    @ObservedObject var recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipeImage(recipe: recipe, cornerRadius: 16).aspectRatio(1, contentMode: .fit)
            Text(recipe.displayTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            if recipe.minutes > 0 {
                Label(durationText(recipe.minutes), systemImage: "clock").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }
}
