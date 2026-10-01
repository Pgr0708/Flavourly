import SwiftUI

/// Shared with Preferences so every quiz answer stays editable later.
struct PersonalizationQuestion {
    let id: String
    let title: String
    let subtitle: String
    let options: [String]
    let symbol: String
    let multiple: Bool
    var grid = false
    var exclusive: String? = nil
}

struct CustomizationScreenView: View {
    @EnvironmentObject private var settings: SettingsManager

    private let green = Color(hex: "#155634")
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    static let questions: [PersonalizationQuestion] = [
        .init(id: "name", title: "What should we call you?", subtitle: "Let's make your kitchen feel like yours.", options: [], symbol: "person.fill", multiple: false),
        .init(id: "goals", title: "What are your goals?", subtitle: "Choose everything you'd like Flavourly to remember.", options: ["Eat healthier", "Lose weight", "Gain muscle", "Save time", "Cook better", "Manage family meals"], symbol: "heart.fill", multiple: true),
        .init(id: "diet", title: "Any dietary preferences?", subtitle: "Select all that apply to your meals.", options: ["No preference", "Vegetarian", "Eggetarian", "Vegan", "Pescatarian", "Jain", "No onion / garlic", "Halal", "Keto", "Low carb", "Gluten free", "Dairy free"], symbol: "leaf.fill", multiple: true, grid: true, exclusive: "No preference"),
        .init(id: "allergies", title: "What must we avoid?", subtitle: "Allergies are hard constraints. Include every ingredient that must stay out.", options: ["None known", "Wheat", "Gluten", "Peanuts", "Tree nuts", "Milk", "Eggs", "Soy", "Fish", "Shellfish", "Sesame", "Other"], symbol: "cross.case.fill", multiple: true, grid: true, exclusive: "None known"),
        .init(id: "dislikes", title: "Any foods you dislike?", subtitle: "We'll remember ingredients and flavours you would rather skip.", options: [], symbol: "hand.thumbsdown.fill", multiple: true),
        .init(id: "cuisines", title: "Which cuisines excite you?", subtitle: "Pick a few favourites. You can explore others later.", options: ["Any cuisine", "Italian", "Indian", "Mediterranean", "Mexican", "Japanese", "Chinese", "Thai", "Middle Eastern", "American", "French", "Korean", "Spanish", "Greek", "Turkish", "Vietnamese", "Caribbean", "African", "Latin American", "British"], symbol: "fork.knife", multiple: true, grid: true, exclusive: "Any cuisine"),
        .init(id: "maxTime", title: "How much time can you cook?", subtitle: "Choose your maximum time for a typical meal.", options: ["15 minutes", "30 minutes", "45 minutes", "60 minutes", "No limit"], symbol: "clock.fill", multiple: false, grid: true),
        .init(id: "skill", title: "How confident are you cooking?", subtitle: "We'll match the level of guidance to you.", options: ["Just starting", "Comfortable with basics", "Confident home cook", "Very experienced"], symbol: "flame.fill", multiple: false),
        .init(id: "frequency", title: "How often do you want to cook?", subtitle: "Your plan should fit your real week.", options: ["Daily", "4–5 times a week", "2–3 times a week", "Once a week", "Mostly meal prep"], symbol: "calendar", multiple: false),
        .init(id: "schedule", title: "When do you need help?", subtitle: "Choose the moments that get busy.", options: ["Weekday breakfasts", "Weekday lunches", "Weeknight dinners", "Weekends", "Meal prep days", "Flexible schedule"], symbol: "calendar.badge.clock", multiple: true),
        .init(id: "modes", title: "What kind of meals fit your day?", subtitle: "Quick meals and snacks can be part of your plan.", options: ["Quick meals", "Snacks", "One-pot meals", "Batch cooking", "Leftovers", "Full meals"], symbol: "timer", multiple: true, grid: true),
        .init(id: "planTypes", title: "Pick your plan styles", subtitle: "Mix and match. You can change these later.", options: ["Balanced", "Mediterranean", "High protein", "Low calorie", "Vegetarian", "Vegan", "Pescatarian", "Keto", "Low carb", "Gluten free", "Dairy free", "Low sodium", "Heart healthy", "Family friendly", "Budget friendly", "Meal prep", "Quick meals", "Plant forward"], symbol: "square.grid.2x2.fill", multiple: true, grid: true),
        .init(id: "household", title: "Who are you cooking for?", subtitle: "We'll remember the people at your table.", options: ["Just me", "Partner and me", "Family of 3–4", "Family of 5+"], symbol: "person.2.fill", multiple: false),
        .init(id: "recipeControls", title: "How do you like to adapt recipes?", subtitle: "Tell us what you expect to control.", options: ["Scale servings", "Remove ingredients", "Swap ingredients", "Lock favourite meals"], symbol: "slider.horizontal.3", multiple: true),
        .init(id: "nutrition", title: "Do you have nutrition targets?", subtitle: "Optional daily goals. Leave blank if you prefer a flexible plan.", options: [], symbol: "chart.bar.fill", multiple: true),
        .init(id: "discovery", title: "Nothing saved yet?", subtitle: "Choose how you'd like to discover your first recipes.", options: ["Browse curated recipes", "Suggest from my tastes", "Use what is in my pantry", "Surprise me"], symbol: "sparkles", multiple: false),
        .init(id: "tracking", title: "What would you like to track?", subtitle: "Choose what matters to you. You can connect Apple Health any time.", options: ["Meals", "Calories and macros", "Cooking progress", "Apple Health"], symbol: "heart.text.square.fill", multiple: true)
    ]

    private var step: Int { settings.customizationStep }
    private var preferences: CustomizationPreferences { settings.customizationPreferences }

    private var question: PersonalizationQuestion {
        Self.questions[min(step, Self.questions.count - 1)]
    }

    private var selected: [String] {
        preferences.choices[question.id] ?? []
    }

    private var canContinue: Bool {
        if question.id == "name" {
            return !settings.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !question.options.isEmpty && selected.isEmpty { return false }
        if question.id == "allergies" && selected.contains("Other")
            && (preferences.notes["otherAllergies"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if question.id == "nutrition" {
            return ["calories", "protein", "carbs", "fat"].allSatisfy { key in
                let value = preferences.notes[key] ?? ""
                return value.isEmpty || (Int(value).map { $0 > 0 && $0 <= 6000 } ?? false)
            }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button {
                        settings.customizationStep -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Previous question")
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()
                Text("\(step + 1) of \(Self.questions.count)")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .foregroundStyle(green)
            .padding(.horizontal, 20)

            GeometryReader { proxy in
                Capsule()
                    .fill(green.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(green)
                            .frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(Self.questions.count))
                    }
            }
            .frame(height: 5)
            .padding(.horizontal, 30)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(question.title)
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(hex: "#172B20"))
                    .fixedSize(horizontal: false, vertical: true)
                Text(question.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#69746B"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 32)
            .padding(.bottom, 22)

            ScrollView {
                VStack(spacing: 12) {
                    if question.id == "name" {
                        Image("HomeEmptyPot")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 190)
                            .accessibilityHidden(true)
                        TextField("Your first name", text: Binding(
                            get: { settings.userName },
                            set: { settings.userName = String($0.prefix(40)) }
                        ))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    if question.grid {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(question.options, id: \.self) { option in
                                choiceCard(option)
                            }
                        }
                    } else {
                        ForEach(question.options, id: \.self) { option in
                            choiceCard(option)
                        }
                    }

                    if question.id == "dislikes" {
                        noteField("Ingredients or flavours", key: "dislikes", prompt: "e.g. mushrooms, cilantro")
                    }
                    if question.id == "allergies" && selected.contains("Other") {
                        noteField("Other allergy", key: "otherAllergies", prompt: "Enter the exact ingredient")
                    }
                    if question.id == "household" {
                        noteField("Household allergies or dislikes", key: "householdNeeds", prompt: "Optional details for your family")
                    }
                    if question.id == "nutrition" {
                        noteField("Daily calories", key: "calories", prompt: "Optional", number: true)
                        noteField("Protein (g)", key: "protein", prompt: "Optional", number: true)
                        noteField("Carbs (g)", key: "carbs", prompt: "Optional", number: true)
                        noteField("Fat (g)", key: "fat", prompt: "Optional", number: true)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
            .id(step)
            .scrollDismissesKeyboard(.interactively)

            Button {
                if step == Self.questions.count - 1 {
                    settings.hasSeenCustomization = true
                } else {
                    settings.customizationStep += 1
                }
            } label: {
                Text(step == Self.questions.count - 1 ? "See My Plan" : "Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(canContinue ? green : green.opacity(0.4), in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(!canContinue)
            .padding(.horizontal, 30)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#F7FBF5"), Color(hex: "#FFFAEF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.light)
        .onAppear {
            settings.customizationStep = min(max(step, 0), Self.questions.count - 1)
        }
    }

    private func choiceCard(_ option: String) -> some View {
        let isSelected = selected.contains(option)
        return Button {
            var updated = preferences
            updated.select(
                option,
                for: question.id,
                options: question.options,
                multiple: question.multiple,
                exclusive: question.exclusive
            )
            settings.customizationPreferences = updated
        } label: {
            HStack(spacing: 11) {
                Image(systemName: question.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(green)
                    .frame(width: 31, height: 31)
                    .background(green.opacity(0.1), in: Circle())
                Text(option)
                    .font(.system(size: question.grid ? 13 : 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#26392B"))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(green)
                }
            }
            .padding(.horizontal, question.grid ? 10 : 15)
            .frame(maxWidth: .infinity, minHeight: question.grid ? 78 : 57)
            .background(isSelected ? Color(hex: "#E7F3E1") : .white.opacity(0.88), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(isSelected ? green.opacity(0.45) : Color(hex: "#E6E8DD"), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func noteField(_ title: String, key: String, prompt: String, number: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(green)
            TextField(prompt, text: Binding(
                get: { preferences.notes[key] ?? "" },
                set: {
                    var updated = preferences
                    updated.notes[key] = String($0.prefix(200))
                    settings.customizationPreferences = updated
                }
            ))
            .keyboardType(number ? .numberPad : .default)
            .textInputAutocapitalization(number ? .never : .sentences)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
