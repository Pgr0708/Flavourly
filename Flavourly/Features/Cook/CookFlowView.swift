import CoreData
import SwiftUI

struct CookTimer: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let ends: Date
    let total: Int

    func remaining(at now: Date) -> Int { max(0, Int(ends.timeIntervalSince(now).rounded(.up))) }
}

/// Full-screen Cook Mode: one step at a time, several timers, then the "done" screen.
struct CookFlowView: View {
    @ObservedObject var recipe: Recipe
    let servings: Int
    var swaps: [UUID: String] = [:]
    var meal: PlannedMeal?

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var timers: [CookTimer] = []
    @State private var now = Date.now
    @State private var finished = false
    @State private var showIngredients = false
    @State private var confirmExit = false
    @State private var checked: Set<UUID> = []

    private var steps: [RecipeStep] { recipe.sortedSteps }
    private var scale: Double { Double(servings) / Double(max(recipe.servings, 1)) }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        ZStack {
            if finished {
                CookDoneView(recipe: recipe, servings: servings, meal: meal) { dismiss() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                cooking.transition(.opacity)
            }
        }
        .animation(Theme.spring, value: finished)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timers.forEach { NotificationService.shared.cancelTimer(id: $0.id.uuidString) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !timers.isEmpty else { continue }
                now = .now
                ringFinishedTimers()
            }
        }
    }

    private var cooking: some View {
        VStack(spacing: 0) {
            topBar
            progress.padding(.horizontal, 20).padding(.top, 10)
            if !timers.isEmpty { timerStrip.padding(.top, 12) }
            if steps.isEmpty {
                ScrollView { ingredientList.padding(20) }
            } else {
                TabView(selection: $index) {
                    ForEach(Array(steps.enumerated()), id: \.element.objectID) { position, step in
                        stepPage(step, number: position + 1).tag(position)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: index) { _, _ in Haptics.step() }
            }
            bottomBar
        }
        .background(Theme.canvas.ignoresSafeArea())
        .sheet(isPresented: $showIngredients) {
            NavigationStack {
                ScrollView { ingredientList.padding(20) }
                    .navigationTitle("Ingredients · \(plural(servings, "serving"))")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showIngredients = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Stop cooking?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Stop and close", role: .destructive) { dismiss() }
            Button("I finished — mark as cooked") { finish() }
        } message: {
            Text(timers.isEmpty ? "Your progress won't be saved." : "Running timers will be cancelled.")
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            IconButton(systemImage: "xmark", label: "Close cook mode", style: .bordered) {
                if index == 0 && timers.isEmpty { dismiss() } else { confirmExit = true }
            }
            Spacer()
            VStack(spacing: 1) {
                Text(recipe.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(steps.isEmpty ? "Ingredients" : "Step \(index + 1) of \(steps.count)")
                    .font(Theme.micro).foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }
            Spacer()
            IconButton(systemImage: "list.bullet", label: "Show ingredients", style: .bordered) { showIngredients = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(steps.count, 1), id: \.self) { position in
                Capsule()
                    .fill(position <= index ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Theme.line))
                    .frame(height: 5)
            }
        }
        .animation(Theme.snappy, value: index)
        .accessibilityHidden(true)
    }

    private var timerStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(timers) { timer in
                    let left = timer.remaining(at: now)
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.3), lineWidth: 3)
                            Circle().trim(from: 0, to: CGFloat(left) / CGFloat(max(timer.total, 1)))
                                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(clock(left)).font(Theme.rounded(17).monospacedDigit()).contentTransition(.numericText(countsDown: true))
                            Text(timer.label).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        Button {
                            cancel(timer)
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                        }
                        .accessibilityLabel("Cancel \(timer.label) timer")
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 7)
                    .background(Theme.flameTextGradient, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(timer.label) timer, \(left / 60) minutes \(left % 60) seconds left")
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func stepPage(_ step: RecipeStep, number: Int) -> some View {
        let used = ingredients(in: step.text ?? "")
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("STEP \(number)").font(Theme.label).tracking(1).foregroundStyle(Theme.capture)
                Text(step.text ?? "")
                    .font(.system(size: 25, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                if !used.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You'll need").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(used, id: \.self) { line in
                                HStack(spacing: 6) {
                                    IngredientIcon(name: IngredientParser.parse(line).name, size: 22)
                                    Text(line).font(.system(size: 14, weight: .medium))
                                }
                                .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
                                .background(.white, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.line))
                            }
                        }
                    }
                }
                if step.timerSeconds > 0 {
                    let label = "Step \(number)"
                    let running = timers.contains { $0.label == label }
                    PrimaryButton(title: running ? "Timer running" : "Start \(durationLabel(Int(step.timerSeconds))) timer",
                                  systemImage: running ? "timer" : "play.fill", tone: running ? .soft : .flame, isEnabled: !running, height: 50) {
                        start(label: label, seconds: Int(step.timerSeconds))
                    }
                }
                Menu {
                    ForEach([1, 3, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) min") { start(label: "Step \(number) · \(minutes)m", seconds: minutes * 60) }
                    }
                } label: {
                    Label("Add a custom timer", systemImage: "plus.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.green)
                }
            }
            .padding(24)
        }
    }

    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(recipe.sortedIngredients) { item in
                let line = lineFor(item)
                if let line {
                    Button {
                        guard let id = item.uuid else { return }
                        Haptics.tick()
                        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
                    } label: {
                        HStack(spacing: 12) {
                            CheckCircle(isOn: item.uuid.map(checked.contains) ?? false)
                            Text(line)
                                .font(.system(size: 17))
                                .strikethrough(item.uuid.map(checked.contains) ?? false)
                                .foregroundStyle(item.uuid.map(checked.contains) ?? false ? Theme.muted : Theme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if !steps.isEmpty && index > 0 {
                PrimaryButton(title: "Back", systemImage: "chevron.left", tone: .outline) {
                    withAnimation(Theme.spring) { index -= 1 }
                }
                .frame(width: 120)
            }
            PrimaryButton(title: steps.isEmpty || isLast ? "Finish cooking" : "Next step",
                          systemImage: steps.isEmpty || isLast ? "checkmark" : "chevron.right",
                          tone: steps.isEmpty || isLast ? .flame : .green) {
                if steps.isEmpty || isLast { finish() } else { withAnimation(Theme.spring) { index += 1 } }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Logic

    private func lineFor(_ item: RecipeIngredient) -> String? {
        if let id = item.uuid, let swap = swaps[id] { return swap.isEmpty ? nil : swap }
        return [item.amount(system: settings.unitSystem, scale: scale), item.name ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Ingredients this step mentions, with amounts for today's servings.
    private func ingredients(in text: String) -> [String] {
        let words = " " + FoodText.normalize(text) + " "
        return recipe.sortedIngredients.compactMap { item in
            let key = FoodText.key(item.name ?? "")
            guard !key.isEmpty, let last = key.split(separator: " ").last, words.contains(" \(last)") else { return nil }
            return lineFor(item)
        }
    }

    private func start(label: String, seconds: Int) {
        let timer = CookTimer(label: label, ends: .now.addingTimeInterval(TimeInterval(seconds)), total: seconds)
        withAnimation(Theme.spring) { timers.append(timer) }
        Haptics.primary()
        Task {
            if await !NotificationService.shared.isAuthorized() { _ = await NotificationService.shared.requestAuthorization() }
            NotificationService.shared.scheduleTimer(id: timer.id.uuidString, title: "\(label) timer is done",
                                                     body: recipe.displayTitle, seconds: seconds)
        }
        DropsManager.showInfo(title: "\(durationLabel(seconds)) timer started", subtitle: "We'll alert you even if you leave the app")
    }

    private func cancel(_ timer: CookTimer) {
        NotificationService.shared.cancelTimer(id: timer.id.uuidString)
        Haptics.destructive()
        withAnimation(Theme.spring) { timers.removeAll { $0.id == timer.id } }
    }

    private func ringFinishedTimers() {
        let done = timers.filter { $0.remaining(at: now) == 0 }
        guard !done.isEmpty else { return }
        withAnimation(Theme.spring) { timers.removeAll { done.contains($0) } }
        Haptics.success()
        DropsManager.showSuccess(title: "\(done[0].label) timer is done", subtitle: recipe.displayTitle)
    }

    private func finish() {
        timers.forEach { NotificationService.shared.cancelTimer(id: $0.id.uuidString) }
        timers.removeAll()
        Haptics.success()
        finished = true
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min" : "\(seconds) sec"
    }
}

// MARK: - Done

struct CookDoneView: View {
    @ObservedObject var recipe: Recipe
    let servings: Int
    var meal: PlannedMeal?
    let onClose: () -> Void

    @EnvironmentObject private var settings: SettingsManager
    @State private var rating = 0
    @State private var reactions: Set<String> = []
    @State private var note = ""
    @State private var logMeal = true
    @State private var keepLeftovers = false
    @State private var celebrate = true

    private let options = ["Make again", "Family favourite", "Kids loved it", "Too salty", "Needs more spice", "Took longer than said"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Theme.cookedWash).frame(width: 190, height: 190)
                    RecipeImage(recipe: recipe, cornerRadius: 70).frame(width: 140, height: 140)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.white, Theme.green)
                                .symbolEffect(.bounce, value: celebrate)
                        }
                }
                .padding(.top, 30)
                VStack(spacing: 6) {
                    Text("Nice cooking!").font(Theme.brand(36)).foregroundStyle(Theme.ink)
                    Text("\(recipe.displayTitle) · \(plural(servings, "serving"))").font(Theme.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Text("How was it?").font(Theme.rowTitle)
                    StarRating(rating: rating, size: 32) { rating = $0 }
                }
                .frame(maxWidth: .infinity)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Anything to remember?").font(Theme.rowTitle)
                    FlowLayout(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Chip(title: option, isOn: reactions.contains(option), style: .green, small: true) {
                                if reactions.contains(option) { reactions.remove(option) } else { reactions.insert(option) }
                            }
                        }
                    }
                    TextField("A note for next time (optional)", text: $note, axis: .vertical)
                        .font(Theme.hand(17))
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    FieldError(message: Validate.optional(note, field: "Note", max: 500, multiline: true).message)
                }
                .card()

                VStack(spacing: 4) {
                    if recipe.hasNutrition {
                        ToggleRow(title: "Log a serving to today", subtitle: "\(Int(recipe.calories)) kcal · \(Int(recipe.protein)) g protein",
                                  systemImage: "chart.pie.fill", isOn: $logMeal)
                    }
                    ToggleRow(title: "Save leftovers to pantry", subtitle: "Reminds you to use them within 3 days",
                              systemImage: "takeoutbag.and.cup.and.straw.fill", tint: Theme.pantry, isOn: $keepLeftovers)
                }
                .card(padding: 8)

                PrimaryButton(title: "Save & close", systemImage: "checkmark", tone: .green) { save() }
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay { if celebrate { ConfettiView().ignoresSafeArea() } }
        .onAppear { rating = Int(recipe.rating) }
    }

    private func save() {
        let check = Validate.optional(note, field: "Note", max: 500, multiline: true)
        guard check.isValid else {
            Haptics.error()
            DropsManager.showError(title: "Please shorten your note", subtitle: check.message)
            return
        }
        let text = (reactions.sorted() + [check.value]).filter { !$0.isEmpty }.joined(separator: " · ")
        Kitchen.recordCooked(recipe, rating: rating, note: text, meal: meal)
        if logMeal && recipe.hasNutrition {
            Kitchen.log(recipe: recipe, slot: meal?.mealSlot ?? .at(hour: Calendar.current.component(.hour, from: .now)))
        }
        if keepLeftovers {
            Kitchen.addPantry(name: "Leftover \(recipe.displayTitle.lowercased())", quantity: 1, unit: "portion",
                              location: .fridge, expires: Calendar.current.date(byAdding: .day, value: 3, to: .now))
        }
        DropsManager.showSuccess(title: "Saved to your cooking history",
                                 subtitle: recipe.cookedCount > 1 ? "Cooked \(recipe.cookedCount) times now" : "First time cooking this — nice!")
        onClose()
    }
}
