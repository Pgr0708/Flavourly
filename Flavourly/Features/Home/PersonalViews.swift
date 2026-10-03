import SwiftUI

// MARK: - Mood chips

/// "How's today?": one tap reshapes every suggestion. A guess from the cook's own history is pre-marked.
struct MoodBar: View {
    @ObservedObject private var personal = Personalizer.shared

    var body: some View {
        let guess = personal.pickedMood == nil ? personal.suggestedMood : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("How's today?").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                if let guess {
                    Text("Usually \(Lang.text(guess.label).lowercased()) at this time")
                        .font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Mood.allCases) { mood in
                        let picked = personal.pickedMood == mood
                        Button {
                            Haptics.select()
                            withAnimation(Theme.snappy) { personal.pick(picked ? nil : mood) }
                        } label: {
                            Label(LocalizedStringKey(mood.label), systemImage: mood.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(picked ? .white : Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(picked ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.chip), in: Capsule())
                                .overlay {
                                    if guess == mood { Capsule().strokeBorder(Theme.green, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Right now

/// The single best dish for this moment — time of day, mood, pantry and habits — with why.
struct RightNowCard: View {
    let picks: [Ranked]
    @State private var index = 0

    var body: some View {
        let shown = picks.indices.contains(index) ? picks[index] : nil
        if let shown, let recipe = Kitchen.recipe(forKey: shown.id) {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: recipe.route) {
                    ZStack(alignment: .bottomLeading) {
                        RecipeImage(recipe: recipe, cornerRadius: 0).frame(height: 210)
                        LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RIGHT NOW").font(Theme.label).tracking(0.8).foregroundStyle(Color(hex: "#CDEBC0"))
                            Text(recipe.displayTitle).font(Theme.heading(22, .bold)).foregroundStyle(.white).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let reason = shown.reasons.first {
                                Label(reason, systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                            }
                        }
                        .padding(16)
                    }
                    .frame(height: 210)
                    .clipped()
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    if recipe.minutes > 0 {
                        Label(durationText(recipe.minutes), systemImage: "clock").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button {
                        Haptics.tick()
                        Personalizer.shared.record(.skip, recipe: shown.id) // not this one: learn from it
                        withAnimation(Theme.spring) { index = (index + 1) % max(picks.count, 1) }
                    } label: {
                        Label("Something else", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tint(Theme.green)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
            .id(shown.id)
            .transition(.opacity)
        }
    }
}

// MARK: - What Flavourly learned

/// Everything the app learned, in plain words, with a switch to stop and a reset. Data never leaves the
/// cook's phone and iCloud.
struct LearnedView: View {
    @ObservedObject private var personal = Personalizer.shared
    @State private var confirmReset = false

    var body: some View {
        let habits = personal.habits
        List {
            Section {
                Toggle("Learn from my activity", isOn: $personal.isLearning).tint(Theme.green)
            } footer: {
                Text("Searches, recipes you open, when and how long you cook, moods, plans you lock and suggestions you skip. Kept only on your iPhone and your iCloud — never sent to our server.")
            }
            if personal.isLearning {
                Section("Your rhythm") {
                    if let minutes = habits.usualMinutes(at: .now) {
                        row("clock", "Usual cooking time now", Text("\(minutes) min"))
                    }
                    if let hour = habits.usualDinnerHour {
                        row("fork.knife", "Dinner usually starts", Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!, style: .time))
                    }
                    if abs(habits.pace - 1) >= 0.08 {
                        row("speedometer", "Your pace", Text("\(String(format: "%.2f", habits.pace))× recipe time"))
                    }
                    if let mood = habits.likelyMood(at: .now), mood.confidence >= 0.5 {
                        row(mood.mood.symbol, "Usual mood now", Text(LocalizedStringKey(mood.mood.label)))
                    }
                    let learnedRhythm = habits.usualMinutes(at: .now) != nil || habits.usualDinnerHour != nil
                        || abs(habits.pace - 1) >= 0.08 || (habits.likelyMood(at: .now)?.confidence ?? 0) >= 0.5
                    if !learnedRhythm { Text("Cook, search and plan a little — this fills in by itself.").foregroundStyle(Theme.muted) }
                }
                if !habits.topSearches().isEmpty {
                    Section("You often look for") {
                        Text(habits.topSearches().joined(separator: " · ")).foregroundStyle(Theme.ink2)
                    }
                }
                Section {
                    Button("Reset what Flavourly learned", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Deletes your activity on all your devices. Saved recipes, ratings and plans stay.")
                }
            }
        }
        .navigationTitle("What Flavourly learned")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset what Flavourly learned?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                personal.reset()
                Haptics.success()
            }
        }
        .onAppear { personal.relearn() }
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(Theme.ink)
            Spacer()
            value.foregroundStyle(Theme.muted)
        }
    }
}
