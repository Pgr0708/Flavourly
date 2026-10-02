import SwiftUI

/// "Popular in India 🇮🇳": photo cards of home dishes from the cook's country, on Home and Discover.
struct LocalDishesSection: View {
    @ObservedObject private var local = LocalFood.shared
    @State private var picking = false

    var body: some View {
        let profile = People.profile()
        let dishes = local.dishes.filter { LocalFood.fits($0, profile) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Popular in \(local.countryName) \(local.flag)").font(Theme.section).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("Home-style favourites from every region").font(Theme.micro).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Change") {
                    Haptics.tick()
                    picking = true
                }
                .font(.system(size: 13, weight: .semibold))
                .tint(Theme.green)
                .accessibilityLabel("Change country, now \(local.countryName)")
            }
            if dishes.isEmpty {
                if let problem = local.problem {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").foregroundStyle(Theme.muted)
                        Text(problem).font(Theme.caption).foregroundStyle(Theme.ink2)
                        Spacer()
                        Button("Retry") { Task { await local.load() } }.font(.system(size: 14, weight: .semibold)).tint(Theme.green)
                    }
                    .card(padding: 14)
                } else if local.isLoading || local.dishes.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.chip).frame(width: 210, height: 230).shimmering()
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .disabled(true)
                    .accessibilityLabel("Loading dishes from \(local.countryName)")
                } else {
                    Text("Nothing from \(local.countryName) fits everyone's food rules yet.").font(Theme.caption).foregroundStyle(Theme.muted)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(dishes) { recipe in
                            NavigationLink(value: recipe.route) { LocalDishCard(recipe: recipe) }
                                .buttonStyle(PressableStyle(scale: 0.97))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $picking) { CountryPickerSheet() }
    }
}

private struct LocalDishCard: View {
    @ObservedObject var recipe: Recipe

    private var region: String? {
        recipe.tagList.first { !["vegetarian", "vegan"].contains($0.lowercased()) }
    }
    private var isVeg: Bool { recipe.tagList.contains { ["vegetarian", "vegan"].contains($0.lowercased()) } }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeImage(recipe: recipe, cornerRadius: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.displayTitle)
                    .font(Theme.heading(16, .demiBold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    if recipe.minutes > 0 { Label(durationText(recipe.minutes), systemImage: "clock") }
                    if recipe.calories > 0 { Text("\(Int(recipe.calories)) kcal") }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
        }
        .frame(width: 210, height: 230)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if let region { Text(region).lineLimit(1) }
                if isVeg { Image(systemName: "leaf.fill").foregroundStyle(Theme.green).accessibilityLabel("Vegetarian") }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.92), in: Capsule())
            .padding(10)
            .opacity(region == nil && !isVeg ? 0 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

/// Like "Not sure what to cook?": three local dishes this cook has never made, fresh each day.
struct TryNewCard: View {
    @ObservedObject private var local = LocalFood.shared
    @State private var shuffles = 0

    var body: some View {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        let picks = local.untried(profile: People.profile(), seed: day + shuffles * 7919)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(LinearGradient(colors: [Color(hex: "#9C56E9"), Color(hex: "#E45AC6")], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Try something new today").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text("\(local.cuisine) dishes you haven't cooked yet").font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Haptics.select()
                        withAnimation(Theme.spring) { shuffles += 1 }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "#7B3FC4"))
                            .frame(width: 36, height: 36)
                            .background(Color(hex: "#F1E8FC"), in: Circle())
                    }
                    .accessibilityLabel("Show other dishes")
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(picks) { recipe in
                        NavigationLink(value: recipe.route) {
                            VStack(alignment: .leading, spacing: 6) {
                                RecipeImage(recipe: recipe, cornerRadius: 14)
                                    .aspectRatio(1, contentMode: .fit)
                                Text(recipe.displayTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2, reservesSpace: true)
                                    .multilineTextAlignment(.leading)
                                if recipe.minutes > 0 {
                                    Label(durationText(recipe.minutes), systemImage: "clock").font(.system(size: 10)).foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .id(shuffles)
            }
            .card()
        }
    }
}

/// Searchable list of every country; changes which local dishes, staples and AI ideas the app shows.
struct CountryPickerSheet: View {
    @ObservedObject private var local = LocalFood.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [String] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return LocalFood.countries }
        return LocalFood.countries.filter { LocalFood.name(for: $0).localizedCaseInsensitiveContains(text) || $0.caseInsensitiveCompare(text) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List(matches, id: \.self) { code in
                Button {
                    Haptics.select()
                    local.country = code
                    DropsManager.showSuccess(title: "Local food: \(LocalFood.name(for: code))", subtitle: "Finding favourite home dishes…")
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(LocalFood.flag(for: code)).font(.system(size: 24))
                        Text(LocalFood.name(for: code)).foregroundStyle(Theme.ink)
                        Spacer()
                        if code == local.country { Image(systemName: "checkmark").foregroundStyle(Theme.green).fontWeight(.bold) }
                    }
                }
                .accessibilityAddTraits(code == local.country ? .isSelected : [])
            }
            .listStyle(.plain)
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
            .navigationTitle("Where do you cook?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
