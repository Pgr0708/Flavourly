import PhotosUI
import SwiftUI

/// Create or edit a recipe. Unsaved work is kept on disk, structural edits can be undone,
/// and ingredient lines are parsed live so bad amounts are caught before saving.
struct RecipeEditorView: View {
    let recipe: Recipe?

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecipeDraft()
    @State private var original = RecipeDraft()
    @State private var history: [RecipeDraft] = []
    @State private var imageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var pasteTarget: PasteTarget?
    @State private var confirmDiscard = false
    @State private var didLoad = false
    @State private var showErrors = false
    @FocusState private var focused: UUID?

    enum PasteTarget: String, Identifiable { case ingredients, steps; var id: String { rawValue } }

    private var storageKey: String { AppStorageKeys.editorDraftPrefix + (recipe?.key ?? "new") }
    private var fields: RecipeDraftFields {
        RecipeDraftFields(title: draft.title, summary: draft.summary ?? "", cuisine: draft.cuisine ?? "", servings: draft.servings,
                          minutes: draft.prepMinutes + draft.cookMinutes, tags: draft.tags,
                          ingredients: draft.ingredients.map(\.text), steps: draft.steps.map(\.text))
    }

    /// Empty required fields only complain after the user tried to save.
    private func shown(_ message: String?, typed: String?) -> String? {
        showErrors || !(typed ?? "").isEmpty ? message : nil
    }

    private var tagsMessage: String? {
        if draft.tags.count > Validate.Limit.tags { return "Up to \(Validate.Limit.tags) tags" }
        return draft.tags.contains { $0.count > Validate.Limit.tag } ? "Tags can be up to \(Validate.Limit.tag) characters" : nil
    }
    private var isDirty: Bool { draft != original || imageData != nil }

    var body: some View {
        List {
            Section { header }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            Section("Basics") {
                Stepper(value: $draft.servings, in: 1...40) {
                    Label("Serves \(draft.servings)", systemImage: "person.2")
                }
                Stepper(value: $draft.prepMinutes, in: 0...600, step: 5) {
                    Label("Prep \(draft.prepMinutes == 0 ? "—" : durationText(draft.prepMinutes))", systemImage: "hand.raised")
                }
                Stepper(value: $draft.cookMinutes, in: 0...720, step: 5) {
                    Label("Cook \(draft.cookMinutes == 0 ? "—" : durationText(draft.cookMinutes))", systemImage: "flame")
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Cuisine (e.g. Indian, Italian)", text: Binding(get: { draft.cuisine ?? "" }, set: { draft.cuisine = $0.isEmpty ? nil : $0 }))
                    FieldError(message: Validate.optional(draft.cuisine ?? "", field: "Cuisine", max: Validate.Limit.cuisine).message)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Good for").font(Theme.micro).foregroundStyle(Theme.muted)
                    HStack(spacing: 6) {
                        ForEach(MealSlot.allCases) { slot in
                            let isOn = draft.mealTypes.contains(slot.rawValue)
                            Chip(title: slot.label, isOn: isOn, style: .green, small: true) {
                                if isOn { draft.mealTypes.removeAll { $0 == slot.rawValue } } else { draft.mealTypes.append(slot.rawValue) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Tags, separated by commas", text: Binding(
                        get: { draft.tags.joined(separator: ", ") },
                        set: { draft.tags = Recipe.split($0) }
                    ))
                    FieldError(message: tagsMessage)
                }
            }

            Section {
                ForEach($draft.ingredients) { $item in ingredientRow($item) }
                    .onDelete { offsets in record { draft.ingredients.remove(atOffsets: offsets) } }
                    .onMove { from, to in record { draft.ingredients.move(fromOffsets: from, toOffset: to) } }
                addRow("Add ingredient", systemImage: "plus.circle.fill") {
                    let item = DraftIngredient(line: "")
                    record { draft.ingredients.append(item) }
                    focused = item.id
                }
                addRow("Paste a list", systemImage: "doc.on.clipboard") { pasteTarget = .ingredients }
            } header: {
                Text("Ingredients · \(draft.ingredients.count)")
            } footer: {
                Text("Write one per line, like “200 g spaghetti” or “2 cloves garlic, crushed”. Hold and drag to reorder.")
            }

            Section {
                ForEach($draft.steps) { $step in
                    stepRow($step, number: (draft.steps.firstIndex { $0.id == step.id } ?? 0) + 1)
                }
                    .onDelete { offsets in record { draft.steps.remove(atOffsets: offsets) } }
                    .onMove { from, to in record { draft.steps.move(fromOffsets: from, toOffset: to) } }
                addRow("Add step", systemImage: "plus.circle.fill") {
                    let step = DraftStep(text: "")
                    record { draft.steps.append(step) }
                    focused = step.id
                }
                addRow("Paste steps", systemImage: "doc.on.clipboard") { pasteTarget = .steps }
            } header: {
                Text("Method · \(draft.steps.count) steps")
            } footer: {
                Text("Times like “simmer for 10 minutes” become one-tap timers in Cook Mode.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isDirty { confirmDiscard = true } else { close(clearDraft: true) }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.bold()
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    guard let previous = history.popLast() else { return }
                    Haptics.tick()
                    withAnimation(Theme.gentle) { draft = previous }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(history.isEmpty)
                Spacer()
                if isDirty { Text("Draft saved on this device").font(Theme.micro).foregroundStyle(Theme.muted) }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { close(clearDraft: true) }
            Button("Keep draft for later") { close(clearDraft: false) }
        }
        .sheet(item: $pasteTarget) { target in
            PasteLinesSheet(target: target) { lines in
                record {
                    if target == .ingredients {
                        draft.ingredients.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                        draft.ingredients += lines.map(DraftIngredient.init(line:))
                    } else {
                        draft.steps.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                        draft.steps += lines.map { DraftStep(text: $0) }
                    }
                }
                DropsManager.showSuccess(title: "Added \(lines.count) \(target == .ingredients ? "ingredients" : "steps")")
            }
        }
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .onChange(of: draft) { _, value in persist(value) }
        .onAppear(perform: load)
        .interactiveDismissDisabled(isDirty)
    }

    // MARK: Rows

    private var header: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let recipe, recipe.imageData != nil || recipe.imageName != nil || recipe.imageURL != nil {
                        RecipeImage(recipe: recipe, cornerRadius: 0)
                    } else {
                        LinearGradient(colors: [Theme.greenTint, Theme.cream], startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill").font(.system(size: 24))
                            Text("Add a cover photo").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.green)
                    }
                }
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("Change", systemImage: "photo").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a cover photo")

            VStack(alignment: .leading, spacing: 4) {
                TextField("Recipe name", text: $draft.title, axis: .vertical)
                    .font(Theme.display(28))
                FieldError(message: shown(Validate.recipeTitle(draft.title).message, typed: draft.title))
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 4) {
                TextField("A line about it (optional)", text: Binding(get: { draft.summary ?? "" }, set: { draft.summary = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink2)
                FieldError(message: Validate.optional(draft.summary ?? "", field: "Description", max: Validate.Limit.summary).message)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
    }

    private func ingredientRow(_ item: Binding<DraftIngredient>) -> some View {
        let parsed = IngredientParser.parse(item.wrappedValue.text)
        let empty = item.wrappedValue.text.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(alignment: .top, spacing: 10) {
            IngredientIcon(name: parsed.name, size: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                TextField("e.g. 200 g spaghetti", text: item.text, axis: .vertical)
                    .focused($focused, equals: item.wrappedValue.id)
                if !empty {
                    let problem = Validate.ingredientLine(item.wrappedValue.text).message
                    if let problem {
                        FieldError(message: problem)
                    } else {
                        HStack(spacing: 6) {
                            if let quantity = parsed.quantity {
                                Badge(text: Amount.text(quantity: quantity, max: parsed.quantityMax, unit: parsed.unit, system: settings.unitSystem), tone: .green)
                            }
                            Text(parsed.name).font(Theme.micro).foregroundStyle(Theme.muted)
                            if parsed.isVague { Badge(text: "Vague amount", systemImage: "exclamationmark.triangle.fill", tone: .amber) }
                            if parsed.isOptional { Badge(text: "Optional", tone: .neutral) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stepRow(_ step: Binding<DraftStep>, number: Int) -> some View {
        let seconds = StepTimer.seconds(in: step.wrappedValue.text)
        return HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.green)
                .frame(width: 24, height: 24)
                .background(Theme.greenSoft, in: Circle())
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Describe this step", text: step.text, axis: .vertical)
                    .focused($focused, equals: step.wrappedValue.id)
                FieldError(message: Validate.stepText(step.wrappedValue.text).message)
                if seconds > 0 {
                    Badge(text: seconds >= 60 ? "\(seconds / 60) min timer" : "\(seconds) sec timer", systemImage: "timer", tone: .orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func addRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            Label(title, systemImage: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.green)
        }
    }

    // MARK: Logic

    /// Snapshots the draft before a structural change so Undo can bring it back.
    private func record(_ change: () -> Void) {
        history.append(draft)
        if history.count > 30 { history.removeFirst() }
        withAnimation(Theme.gentle) { change() }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let base = recipe?.draft() ?? {
            var fresh = RecipeDraft()
            fresh.servings = settings.defaultServings
            fresh.ingredients = [DraftIngredient(line: "")]
            fresh.steps = [DraftStep(text: "")]
            return fresh
        }()
        original = base
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(RecipeDraft.self, from: data), saved != base {
            draft = saved
            DropsManager.showInfo(title: "Restored your unsaved changes", subtitle: "Cancel › Discard to start over")
        } else {
            draft = base
        }
    }

    private func persist(_ value: RecipeDraft) {
        guard didLoad else { return }
        if value == original {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                DropsManager.showError(title: "Couldn't open that photo")
                return
            }
            imageData = image.storageJPEG(maxSide: 1600)
            Haptics.success()
        }
    }

    private func save() {
        if let problem = Validate.recipe(fields) {
            withAnimation(Theme.snappy) { showErrors = true }
            Haptics.error()
            DropsManager.showError(title: "Please fix this first", subtitle: problem)
            return
        }
        var final = draft
        final.title = final.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = Dictionary(original.ingredients.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        final.ingredients = final.ingredients
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { before[$0.id] == $0.text ? $0 : DraftIngredient(line: $0.text.trimmingCharacters(in: .whitespaces)) }
        final.steps = final.steps
            .map { DraftStep(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        if final.prepMinutes != original.prepMinutes || final.cookMinutes != original.cookMinutes {
            final.totalMinutes = final.prepMinutes + final.cookMinutes
        }
        final.flags = []
        final.method = final.method ?? "manual"
        let saved = Kitchen.save(final, into: recipe.map(Kitchen.adopt), imageData: imageData)
        if final.ingredients.map(\.text) != original.ingredients.map(\.text) || final.servings != original.servings {
            Task { await Kitchen.refreshNutrition(saved) }
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
        DropsManager.showSuccess(title: recipe == nil ? "Saved to your cookbook" : "Recipe updated", subtitle: saved.displayTitle)
        dismiss()
    }

    private func close(clearDraft: Bool) {
        if clearDraft { UserDefaults.standard.removeObject(forKey: storageKey) }
        dismiss()
    }
}

/// Paste a whole list; bullets and numbering are stripped, one item per line.
struct PasteLinesSheet: View {
    let target: RecipeEditorView.PasteTarget
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var lines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"^\s*(?:[-•*▢☐◦·]|\d+[.)]|step\s*\d+[:.]?)\s*"#, with: "", options: [.regularExpression, .caseInsensitive]) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(target == .ingredients ? "One ingredient per line." : "One step per line.")
                    .font(Theme.caption).foregroundStyle(Theme.muted)
                TextEditor(text: $text)
                    .font(Theme.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
                if text.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.joined(separator: "\n")
                        Haptics.tick()
                    }
                    .tint(Theme.green)
                }
                PrimaryButton(title: lines.isEmpty ? "Add" : "Add \(lines.count) \(target == .ingredients ? "ingredients" : "steps")",
                              systemImage: "plus", isEnabled: !lines.isEmpty) {
                    onAdd(lines)
                    dismiss()
                }
            }
            .padding(20)
            .background(Theme.canvas)
            .navigationTitle(target == .ingredients ? "Paste ingredients" : "Paste steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
