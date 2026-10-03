import SwiftUI

/// One page of the Home strip: a dish (today's plan, a favourite, a pick, something new) or a world kitchen.
struct HomeSlide: Identifiable {
    enum Art {
        case recipe(Recipe)
        case dish(String) // a famous dish's name: free photo looked up by name
    }
    let id: String
    let kicker: LocalizedStringKey
    let title: String
    let subtitle: String?
    let art: Art
    let route: Route
}

/// The top of Home: swipe either way forever, or let it move on by itself every few seconds.
struct HomeCarousel: View {
    let slides: [HomeSlide]
    @State private var position: Int?
    private let pages = 2_000 // lazily built: effectively endless in both directions

    var body: some View {
        if !slides.isEmpty {
            let current = (position ?? pages / 2) % slides.count
            VStack(spacing: 10) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<pages, id: \.self) { index in
                            let slide = slides[index % slides.count]
                            NavigationLink(value: slide.route) { SlideCard(slide: slide) }
                                .buttonStyle(PressableStyle(scale: 0.98))
                                .padding(.horizontal, 4)
                                .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $position)
                .scrollIndicators(.hidden)
                .frame(height: 250)
                .padding(.horizontal, -4)
                HStack(spacing: 6) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule().fill(index == current ? Theme.ink : Theme.line)
                            .frame(width: index == current ? 18 : 6, height: 6)
                    }
                }
                .animation(Theme.snappy, value: current)
                .accessibilityHidden(true)
            }
            .onAppear { if position == nil { position = pages / 2 - (pages / 2) % slides.count } }
            // Moves on 5 s after the last change — a swipe restarts the wait.
            .task(id: position) {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let position else { return }
                withAnimation(.easeInOut(duration: 0.45)) { self.position = position + 1 }
            }
        }
    }
}

private struct SlideCard: View {
    let slide: HomeSlide
    @State private var photo: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch slide.art {
            case .recipe(let recipe): RecipeImage(recipe: recipe, cornerRadius: 0)
            case .dish(let name):
                DishPhoto(url: photo, title: name).task { photo = await WorldKitchens.photo(of: name) }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(slide.kicker).font(Theme.label).tracking(0.8).textCase(.uppercase).foregroundStyle(Color(hex: "#CDEBC0"))
                Text(slide.title).font(Theme.heading(22, .bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                if let subtitle = slide.subtitle {
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
            }
            .padding(16)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
