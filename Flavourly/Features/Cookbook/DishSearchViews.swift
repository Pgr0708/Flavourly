import SwiftUI

/// Under the Cookbook search field: recent searches when empty; while typing, dish names from the cook's
/// country (local first: "alu" → "Aloo Puri · Gujarat"); and when nothing saved matches, ways to still cook it.
struct DishSearchPanel: View {
    @Binding var query: String
    /// Nothing in the cookbook matches the query.
    let noResults: Bool
    let importAction: () -> Void

    @ObservedObject private var personal = Personalizer.shared
    @State private var suggestions: [DishSearch.Suggestion] = []
    @State private var opening: String?
    @State private var opened: Route?

    var body: some View {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 10) {
            if typed.isEmpty {
                recent
            } else {
                if !suggestions.isEmpty { suggestionList }
                if noResults { notFound(typed) }
            }
        }
        .task(id: typed) {
            guard typed.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(300)) // wait until typing pauses
            guard !Task.isCancelled else { return }
            let found = await DishSearch.suggest(typed)
            if !Task.isCancelled { withAnimation(Theme.snappy) { suggestions = found } }
        }
        .navigationDestination(item: $opened) { RouteView(route: $0) }
    }

    @ViewBuilder
    private var recent: some View {
        let terms = personal.recentQueries.isEmpty ? personal.habits.topSearches(5) : Array(personal.recentQueries.prefix(6))
        if !terms.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    ForEach(terms, id: \.self) { term in
                        Button { query = term } label: { chip(term) }.buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { item in
                Button { open(item.name) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife").font(.system(size: 14)).foregroundStyle(Theme.green).frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                            if let region = item.region { Text(region).font(Theme.micro).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        if opening == item.name { ProgressView() } else {
                            Image(systemName: "arrow.up.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(opening != nil)
                if item != suggestions.last { Divider().padding(.leading, 52) }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
    }

    private func notFound(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\u{201C}\(name)\u{201D} isn't in your cookbook").font(Theme.rowTitle).foregroundStyle(Theme.ink)
            PrimaryButton(title: "Get the recipe", systemImage: "magnifyingglass", isLoading: opening == name, height: 46) { open(name) }
            PrimaryButton(title: "Cook it with what I have", systemImage: "sparkles", tone: .outline, height: 46) {
                CookNowModel.shared.open(craving: name)
            }
            Button(action: importAction) {
                Label("Import a recipe for it", systemImage: "link").font(.system(size: 14, weight: .semibold))
            }
            .tint(Theme.green)
            .frame(maxWidth: .infinity)
        }
        .card(padding: 16)
    }

    private func chip(_ term: String) -> some View {
        Text(term)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.chip, in: Capsule())
    }

    private func open(_ name: String) {
        Haptics.select()
        opening = name
        Task {
            defer { opening = nil }
            do {
                let recipe = try await DishSearch.find(name)
                opened = recipe.route
            } catch APIError.premiumRequired {
                DropsManager.showInfo(title: "New dish — Premium", subtitle: "This dish isn't in our library yet. Premium writes it with AI, then it's free for everyone.")
                Paywall.show()
            } catch {
                DropsManager.showError(title: "Couldn't find that dish", subtitle: error.localizedDescription)
            }
        }
    }
}

// MARK: - Recipe videos

/// "Watch it made": YouTube videos for the dish, opened in YouTube (nothing is downloaded).
struct RecipeVideosRow: View {
    let title: String
    @State private var videos: [DishSearch.Video] = []
    @State private var search: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Watch it made", systemImage: "play.rectangle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                if let search {
                    Link(destination: search) { Text("More on YouTube").font(.system(size: 13, weight: .semibold)) }.tint(Theme.green)
                }
            }
            if !videos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(videos) { video in
                            if let url = URL(string: video.url) {
                                Link(destination: url) { videoCard(video) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: title) {
            let result = await DishSearch.videos(for: title)
            videos = result.videos
            search = result.search
        }
    }

    private func videoCard(_ video: DishSearch.Video) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                DishPhoto(url: video.thumbnail, title: title)
                Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(.white).shadow(radius: 6)
            }
            .frame(width: 220, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(video.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2, reservesSpace: true)
            Text(video.channel).font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(width: 220, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens YouTube")
    }
}
