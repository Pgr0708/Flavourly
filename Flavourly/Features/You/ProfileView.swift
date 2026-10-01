import CoreData
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var settings: SettingsManager
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "isSaved == YES AND isArchived == NO")) private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: []) private var members: FetchedResults<HouseholdMember>
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats
                if !settings.isPremium { upgradeCard }
                VStack(spacing: 0) {
                    row(.preferences, "Food preferences", "Allergies, diets, cuisines, time", "slider.horizontal.3", Theme.green)
                    divider
                    row(.household, "Household", members.isEmpty ? "Just you · add family or housemates" : "\(members.count + 1) people · portions & rules",
                        "person.2.fill", Theme.plan)
                    divider
                    row(.nutrition, "Nutrition & goals", targetsText, "chart.pie.fill", Theme.capture)
                    divider
                    row(.healthConnect, "Apple Health", HealthService.shared.isConnected ? "Connected" : "Not connected", "heart.fill", Theme.allergen)
                }
                .card(padding: 4)
                VStack(spacing: 0) {
                    row(.pantry, "Pantry", "What you have at home", "cabinet.fill", Theme.pantry)
                    divider
                    row(.smartCollection(.favourites), "Favourites", nil, "heart.fill", Color(hex: "#D9467A"))
                    divider
                    row(.smartCollection(.archived), "Archived recipes", nil, "archivebox.fill", Theme.ink2)
                    divider
                    row(.settings, "Settings", "Units, notifications, data", "gearshape.fill", Theme.ink2)
                }
                .card(padding: 4)
                Text("No account needed — your kitchen lives on this iPhone and in your iCloud.")
                    .font(Theme.micro).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallScreenView().environmentObject(settings) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(initial: String(settings.displayName.prefix(1)).uppercased(), color: Theme.green, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.displayName).font(Theme.display(30))
                if settings.isPremium {
                    Badge(text: "Premium", systemImage: "crown.fill", tone: .gold)
                } else {
                    Text("Free plan").font(Theme.micro).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
    }

    private var stats: some View {
        let cooked = recipes.reduce(0) { $0 + Int($1.cookedCount) }
        return HStack(spacing: 10) {
            stat("\(recipes.count)", "recipes", "book.fill", Theme.green)
            stat("\(cooked)", "times cooked", "flame.fill", Theme.capture)
            stat("\(members.count + 1)", "at the table", "person.2.fill", Theme.plan)
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(Theme.rounded(24)).contentTransition(.numericText())
            Text(label).font(Theme.micro).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    private var upgradeCard: some View {
        Button {
            Haptics.primary()
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(Theme.premiumDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flavourly Premium").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.premiumDeep)
                    Text("Unlimited imports, AI plans and ideas").font(Theme.micro).foregroundStyle(Theme.premiumDeep.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.premiumDeep)
            }
            .padding(16)
            .background(Theme.premiumGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var targetsText: String {
        let me = People.me()
        if me.calorieTarget == 0 && me.proteinTarget == 0 { return "Log meals · set daily targets" }
        return [me.calorieTarget > 0 ? "\(me.calorieTarget) kcal" : nil, me.proteinTarget > 0 ? "\(me.proteinTarget) g protein" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var divider: some View { Divider().padding(.leading, 56) }

    private func row(_ route: Route, _ title: String, _ subtitle: String?, _ symbol: String, _ tint: Color) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                IconTile(systemImage: symbol, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    if let subtitle { Text(subtitle).font(Theme.micro).foregroundStyle(Theme.muted) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.tick() })
    }
}

// MARK: - Preferences

/// Every setup-quiz answer, editable. These drive recommendations, the planner and Cook Now.
struct PreferencesView: View {
    @EnvironmentObject private var settings: SettingsManager

    private static let order = ["allergies", "diet", "dislikes", "cuisines", "maxTime", "skill", "goals", "frequency", "schedule",
                                "modes", "planTypes", "household", "nutrition", "discovery", "tracking", "recipeControls"]
    private let spice = PersonalizationQuestion(id: "spice", title: "How spicy?", subtitle: "Mild keeps chilli-heavy dishes out of suggestions.",
                                                options: ["Mild", "Medium", "Hot"], symbol: "flame", multiple: false)

    private var questions: [PersonalizationQuestion] {
        let byID = Dictionary(CustomizationScreenView.questions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var list = Self.order.compactMap { byID[$0] }
        list.insert(spice, at: min(3, list.count))
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Everything here shapes your recommendations, plans and Cook Now. Allergies are hard rules — recipes with them are never suggested or planned.")
                    .font(Theme.caption).foregroundStyle(Theme.ink2)
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NAME").font(Theme.label).tracking(0.6).foregroundStyle(Theme.muted)
                    TextField("Your name", text: $settings.userName)
                        .font(.system(size: 17, weight: .medium))
                        .textContentType(.givenName)
                    FieldError(message: Validate.personName(settings.userName).message)
                }
                .card(padding: 14)
                ForEach(questions, id: \.id) { question in questionCard(question) }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("Food preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func questionCard(_ question: PersonalizationQuestion) -> some View {
        let selected = settings.customizationPreferences.choices[question.id] ?? []
        let isAllergy = question.id == "allergies"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: question.symbol).foregroundStyle(isAllergy ? Theme.allergen : Theme.green)
                Text(question.title).font(.system(size: 16, weight: .semibold))
                if isAllergy { Badge(text: "Hard rule", tone: .red) }
            }
            if !question.options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(question.options, id: \.self) { option in
                        Chip(title: option, isOn: selected.contains(option), style: isAllergy ? .red : .green, small: true) {
                            var updated = settings.customizationPreferences
                            updated.select(option, for: question.id, options: question.options, multiple: question.multiple, exclusive: question.exclusive)
                            settings.customizationPreferences = updated
                        }
                    }
                }
            }
            switch question.id {
            case "allergies":
                if selected.contains("Other") { note("Other allergies (exact ingredients)", key: "otherAllergies", prompt: "e.g. kiwi, lupin") }
            case "dislikes":
                note("Ingredients or flavours to skip", key: "dislikes", prompt: "e.g. mushrooms, coriander")
            case "household":
                NavigationLink(value: Route.household) {
                    Label("Add each person's allergies and portions", systemImage: "person.badge.plus").font(.system(size: 13, weight: .semibold))
                }
                .tint(Theme.green)
            case "nutrition":
                HStack(spacing: 8) {
                    note("Calories", key: "calories", prompt: "kcal", number: true)
                    note("Protein", key: "protein", prompt: "g", number: true)
                }
                HStack(spacing: 8) {
                    note("Carbs", key: "carbs", prompt: "g", number: true)
                    note("Fat", key: "fat", prompt: "g", number: true)
                }
            default:
                EmptyView()
            }
        }
        .card(padding: 14)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isAllergy ? Theme.allergen.opacity(0.25) : .clear))
    }

    private func note(_ title: String, key: String, prompt: String, number: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.micro.weight(.semibold)).foregroundStyle(Theme.ink2)
            TextField(prompt, text: Binding(
                get: { settings.customizationPreferences.notes[key] ?? "" },
                set: { value in
                    var updated = settings.customizationPreferences
                    updated.notes[key] = String((number ? value.filter(\.isNumber) : value).prefix(200))
                    settings.customizationPreferences = updated
                }
            ))
            .keyboardType(number ? .numberPad : .default)
            .padding(10)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            FieldError(message: noteProblem(key, settings.customizationPreferences.notes[key] ?? ""))
        }
    }

    private func noteProblem(_ key: String, _ value: String) -> String? {
        switch key {
        case "calories": Validate.integer(value, field: "Calories", range: Validate.Target.calories).message
        case "protein": Validate.integer(value, field: "Protein", range: Validate.Target.protein).message
        case "carbs": Validate.integer(value, field: "Carbs", range: Validate.Target.carbs).message
        case "fat": Validate.integer(value, field: "Fat", range: Validate.Target.fat).message
        case "otherAllergies": Validate.list(value, field: "Other allergies").message
        case "dislikes": Validate.list(value, field: "Dislikes").message
        default: nil
        }
    }
}

// MARK: - Household

struct HouseholdView: View {
    @EnvironmentObject private var settings: SettingsManager
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)])
    private var members: FetchedResults<HouseholdMember>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Everyone's allergies and diets apply to the meals they eat. Portions set how much to cook.")
                    .font(Theme.caption).foregroundStyle(Theme.ink2)
                let me = People.me()
                personRow(route: .preferences, initial: me.initial, color: me.color, name: "\(me.name) (you)",
                          detail: summary(allergies: me.allergies, diets: me.diets, portion: 1))
                ForEach(members) { member in
                    let person = People.person(member)
                    personRow(route: .member(member.objectID), initial: member.initial, color: member.color, name: member.displayName,
                              detail: summary(allergies: person.allergies, diets: person.diets, portion: member.portion, age: member.ageGroup))
                }
                NavigationLink(value: Route.member(nil)) {
                    Label("Add a person", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.greenSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .tint(Theme.green)
            }
            .padding(20)
        }
        .dockSpacing()
        .canvasBackground()
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func personRow(route: Route, initial: String, color: Color, name: String, detail: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Avatar(initial: initial, color: color, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Theme.rowTitle).foregroundStyle(Theme.ink)
                    Text(detail).font(Theme.micro).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .card(padding: 12)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func summary(allergies: [String], diets: [String], portion: Double, age: String? = nil) -> String {
        var parts: [String] = []
        if let age, age != "adult" { parts.append(age.capitalized) }
        if portion != 1 { parts.append("\(portion.formatted()) portion") }
        if !allergies.isEmpty { parts.append("No " + allergies.joined(separator: ", ").lowercased()) }
        if !diets.isEmpty { parts.append(diets.joined(separator: ", ")) }
        return parts.isEmpty ? "No food rules" : parts.joined(separator: " · ")
    }
}

struct MemberEditorView: View {
    let member: HouseholdMember?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = Swatch.all[1]
    @State private var ageGroup = "adult"
    @State private var portion = 1.0
    @State private var allergies: Set<String> = []
    @State private var otherAllergies = ""
    @State private var diets: Set<String> = []
    @State private var dislikes = ""
    @State private var spice = "medium"
    @State private var breakfast = true
    @State private var lunch = true
    @State private var dinner = true
    @State private var calories = ""
    @State private var protein = ""
    @State private var confirmDelete = false
    @State private var didLoad = false
    @State private var showErrors = false

    private var nameCheck: FieldCheck { Validate.personName(name) }
    private var allergyList: (items: [String], message: String?) { Validate.list(otherAllergies, field: "Other allergies") }
    private var dislikeList: (items: [String], message: String?) { Validate.list(dislikes, field: "Dislikes") }
    private var calorieCheck: (value: Int?, message: String?) { Validate.integer(calories, field: "Calories", range: Validate.Target.calories) }
    private var proteinCheck: (value: Int?, message: String?) { Validate.integer(protein, field: "Protein", range: Validate.Target.protein) }
    private var firstProblem: String? {
        nameCheck.message ?? allergyList.message ?? dislikeList.message ?? calorieCheck.message ?? proteinCheck.message
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $name).font(.system(size: 17, weight: .medium))
                    FieldError(message: showErrors || !name.isEmpty ? nameCheck.message : nil)
                }
                HStack(spacing: 10) {
                    ForEach(Swatch.all, id: \.self) { hex in
                        Button {
                            Haptics.select()
                            colorHex = hex
                        } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                .overlay { if hex == colorHex { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(hex)")
                    }
                }
                Picker("Age", selection: $ageGroup) {
                    Text("Adult").tag("adult")
                    Text("Teen").tag("teen")
                    Text("Child").tag("child")
                }
                .pickerStyle(.segmented)
                .onChange(of: ageGroup) { _, value in
                    guard didLoad else { return }
                    portion = value == "child" ? 0.5 : (value == "teen" ? 1 : portion)
                    if value == "child" { spice = "mild" }
                }
                Picker("Portion", selection: $portion) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text($0 == 1 ? "Standard" : "\($0.formatted())×").tag($0) }
                }
            }

            Section {
                FlowLayout(spacing: 6) {
                    ForEach(Allergen.allCases) { allergen in
                        Chip(title: allergen.label, isOn: allergies.contains(allergen.label), style: .red, small: true) {
                            if allergies.contains(allergen.label) { allergies.remove(allergen.label) } else { allergies.insert(allergen.label) }
                        }
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Other allergies (exact ingredients)", text: $otherAllergies)
                    FieldError(message: allergyList.message)
                }
            } header: {
                Text("Allergies — hard rules")
            } footer: {
                Text("Meals \(name.isEmpty ? "they" : name) eat never include these. Imports and swaps are checked too.")
            }

            Section("Diet") {
                FlowLayout(spacing: 6) {
                    ForEach(Diet.allCases) { diet in
                        Chip(title: diet.label, isOn: diets.contains(diet.label), style: .green, small: true) {
                            if diets.contains(diet.label) { diets.remove(diet.label) } else { diets.insert(diet.label) }
                        }
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Dislikes, e.g. mushrooms, olives", text: $dislikes)
                    FieldError(message: dislikeList.message)
                }
                Picker("Spice", selection: $spice) {
                    Text("Mild").tag("mild")
                    Text("Medium").tag("medium")
                    Text("Hot").tag("hot")
                }
            }

            Section("Usually eats") {
                Toggle("Breakfast", isOn: $breakfast)
                Toggle("Lunch at home", isOn: $lunch)
                Toggle("Dinner", isOn: $dinner)
            }

            Section("Daily targets (optional)") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Calories (kcal)", text: $calories).keyboardType(.numberPad)
                    FieldError(message: calorieCheck.message)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Protein (g)", text: $protein).keyboardType(.numberPad)
                    FieldError(message: proteinCheck.message)
                }
            }

            if member != nil {
                Section {
                    Button("Remove from household", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .tint(Theme.green)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(member == nil ? "Add a person" : member?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).bold()
            }
        }
        .confirmationDialog("Remove \(member?.displayName ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let member else { return }
                Kitchen.context.delete(member)
                Kitchen.save()
                Haptics.destructive()
                DropsManager.showInfo(title: "Removed from household")
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        defer { didLoad = true }
        guard let member else {
            colorHex = Swatch.color(for: People.members().count + 1)
            return
        }
        name = member.name ?? ""
        colorHex = member.colorHex ?? colorHex
        ageGroup = member.ageGroup ?? "adult"
        portion = member.portion
        let known = Set(Allergen.allCases.map(\.label))
        let all = Recipe.split(member.allergies)
        allergies = Set(all.filter { known.contains($0) })
        otherAllergies = all.filter { !known.contains($0) }.joined(separator: ", ")
        diets = Set(Recipe.split(member.diets))
        dislikes = Recipe.split(member.dislikes).joined(separator: ", ")
        spice = member.spiceLevel ?? "medium"
        breakfast = member.eatsBreakfast
        lunch = member.eatsLunch
        dinner = member.eatsDinner
        calories = member.calorieTarget > 0 ? "\(member.calorieTarget)" : ""
        protein = member.proteinTarget > 0 ? "\(member.proteinTarget)" : ""
    }

    private func save() {
        if let problem = firstProblem {
            withAnimation(Theme.snappy) { showErrors = true }
            Haptics.error()
            DropsManager.showError(title: "Please fix this first", subtitle: problem)
            return
        }
        let target = member ?? HouseholdMember(context: Kitchen.context)
        if member == nil {
            target.uuid = UUID()
            target.createdAt = .now
            target.sortIndex = Int16(clamping: People.members().count)
        }
        target.name = nameCheck.value
        target.colorHex = colorHex
        target.ageGroup = ageGroup
        target.portion = portion
        target.allergies = (allergies.sorted() + allergyList.items).joined(separator: ",")
        target.diets = diets.sorted().joined(separator: ",")
        target.dislikes = dislikeList.items.joined(separator: ",")
        target.spiceLevel = spice
        target.eatsBreakfast = breakfast
        target.eatsLunch = lunch
        target.eatsDinner = dinner
        target.calorieTarget = Int32(calorieCheck.value ?? 0)
        target.proteinTarget = Int32(proteinCheck.value ?? 0)
        Kitchen.save()
        Haptics.success()
        DropsManager.showSuccess(title: member == nil ? "\(target.displayName) added" : "Saved", subtitle: "Their rules now apply to meals they eat")
        dismiss()
    }
}
