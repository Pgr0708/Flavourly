import SwiftUI

private enum HomeTab: String, CaseIterable {
    case home = "Home"
    case plan = "Plan"
    case recipes = "Recipes"
    case more = "More"

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .plan: "calendar"
        case .recipes: "book.closed.fill"
        case .more: "ellipsis.circle.fill"
        }
    }
}

private enum HomeSheet: String, Identifiable {
    case groceries, recipeLink, scanner, premium
    var id: String { rawValue }
}

private struct RecipeIdea: Identifiable {
    let id: String
    let title: String
    let category: String
    let minutes: Int
    let imageName: String
    let ingredients: [String]
    let directions: [String]

    static let examples: [RecipeIdea] = [
        .init(
            id: "creamy-garlic-pasta",
            title: "Creamy Garlic Pasta",
            category: "Dinner",
            minutes: 25,
            imageName: "SplashPasta",
            ingredients: ["Pasta (contains wheat)", "Cream (contains milk)", "Garlic", "Cherry tomatoes", "Basil"],
            directions: ["Cook the pasta until tender.", "Warm garlic and tomatoes in a pan.", "Stir in cream, toss with pasta and finish with basil."]
        ),
        .init(
            id: "salmon-grain-bowl",
            title: "Salmon Grain Bowl",
            category: "Lunch",
            minutes: 30,
            imageName: "OnboardingPlan",
            ingredients: ["Salmon (contains fish)", "Quinoa", "Avocado", "Broccoli", "Cherry tomatoes"],
            directions: ["Cook the quinoa and roast the salmon.", "Prepare the vegetables.", "Arrange everything in a bowl and serve."]
        )
    ]
}

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsManager
    @State private var selectedTab: HomeTab = .home
    @State private var activeSheet: HomeSheet?
    @State private var selectedIdea: RecipeIdea?
    @State private var showingAddMenu = false
    @State private var searchText = ""
    @State private var recipeFilter = "All"

    private let ink = Color(hex: "#172333")
    private let green = Color(hex: "#155634")
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let filters = ["All", "Breakfast", "Lunch", "Dinner"]

    private var canShowRecipeIdeas: Bool {
        let preferences = settings.customizationPreferences
        let allergies = preferences.choices["allergies"] ?? []
        let diets = preferences.choices["diet"] ?? []
        return allergies.allSatisfy { $0 == "None known" }
            && diets.allSatisfy { $0 == "No preference" }
            && (preferences.notes["dislikes"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingIdeas: [RecipeIdea] {
        guard canShowRecipeIdeas else { return [] }
        return RecipeIdea.examples.filter {
            (recipeFilter == "All" || $0.category == recipeFilter)
            && (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .home: dashboard
            case .plan: planScreen
            case .recipes: recipesScreen
            case .more: moreScreen
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .background(Color(hex: "#FAFBF9"))
        .preferredColorScheme(.light)
        .confirmationDialog("Add to Flavourly", isPresented: $showingAddMenu) {
            Button("Add a meal to my week") { selectedTab = .plan }
            Button("Add a grocery item") { activeSheet = .groceries }
            Button("Save a recipe link") { activeSheet = .recipeLink }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .groceries:
                GroceryListSheet()
                    .environmentObject(settings)
            case .recipeLink:
                SaveRecipeLinkSheet()
                    .environmentObject(settings)
            case .scanner:
                scannerSheet
            case .premium:
                PaywallScreenView()
                    .environmentObject(settings)
            }
        }
        .sheet(item: $selectedIdea) { idea in
            RecipeIdeaSheet(idea: idea)
                .environmentObject(settings)
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let hour = Calendar.current.component(.hour, from: context.date)
                    homeHeader(moment: HomeMoment(hour: hour))
                }

                VStack(alignment: .leading, spacing: 24) {
                    weeklyPlanBadge

                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Quick Actions")
                        HStack(alignment: .top, spacing: 8) {
                            quickAction("Import Recipe", symbol: "square.and.arrow.down.fill", color: Color(hex: "#FF8D35")) {
                                activeSheet = .recipeLink
                            }
                            quickAction("Scan Food", symbol: "viewfinder", color: Color(hex: "#24ADB5")) {
                                activeSheet = .scanner
                            }
                            quickAction("Create Plan", symbol: "calendar.badge.plus", color: Color(hex: "#E45AC6")) {
                                selectedTab = .plan
                            }
                            quickAction("Grocery List", symbol: "basket.fill", color: Color(hex: "#9C56E9")) {
                                activeSheet = .groceries
                            }
                        }
                    }

                    recipeIdeasSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func homeHeader(moment: HomeMoment) -> some View {
        GeometryReader { geometry in
        ZStack {
            Image(moment.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: 260)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.52), .black.opacity(0.06), .black.opacity(0.32)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("\(moment.greeting)\n\(settings.displayName)! 👋")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 5)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        selectedTab = .more
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.44), in: Circle())
                    }
                    .accessibilityLabel("Open profile")
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.gray)
                    TextField("", text: $searchText, prompt: Text("Search recipes, ingredients...").foregroundColor(Color(hex: "#67707A")))
                        .foregroundStyle(ink)
                        .submitLabel(.search)
                        .onSubmit { selectedTab = .recipes }
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.gray)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 15)
                .frame(height: 44)
                .background(.white.opacity(0.96), in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
            .padding(.horizontal, 22)
            .padding(.top, 62)
            .padding(.bottom, 18)
        }
        .frame(width: geometry.size.width, height: 260)
        .clipped()
        }
        .frame(height: 260)
    }

    private var weeklyPlanBadge: some View {
        Button {
            selectedTab = .plan
        } label: {
            GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Image("WeeklyPlanCard")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: 126)
                    .clipped()
                    .scaleEffect(1.15)
                    .accessibilityHidden(true)
                LinearGradient(
                    colors: [Color(hex: "#F53F86").opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Weekly Plan")
                        .font(.system(size: 17, weight: .bold))
                    Text("\(settings.homeData.plannedDayCount)/7 meals planned")
                        .font(.system(size: 13))
                    Text("View Plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#BD3870"))
                        .padding(.horizontal, 21)
                        .padding(.vertical, 8)
                        .background(.white, in: Capsule())
                        .padding(.top, 5)
                }
                .foregroundStyle(.white)
                .padding(.leading, 17)
            }
            .frame(width: geometry.size.width, height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 17))
            }
            .frame(height: 126)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your weekly plan, \(settings.homeData.plannedDayCount) of 7 meals planned. View plan")
    }

    private func quickAction(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 54, height: 54)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var recipeIdeasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("For You")
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        recipeFilter = filter
                    } label: {
                        Text(filter)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(recipeFilter == filter ? .white : ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(recipeFilter == filter ? ink : Color(hex: "#F0F1F2"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if matchingIdeas.isEmpty {
                recipeEmptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(matchingIdeas) { idea in
                            recipeCard(idea)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var recipeEmptyState: some View {
        VStack(spacing: 7) {
            Image("HomeEmptyPot")
                .resizable()
                .scaledToFit()
                .frame(height: 105)
                .accessibilityHidden(true)
            Text(canShowRecipeIdeas ? "No recipes match this search yet" : "Your food preferences are saved")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
            Text(canShowRecipeIdeas
                 ? "Try another meal type or save a recipe link."
                 : "Verified recipe suggestions for your restrictions are being prepared.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func recipeCard(_ idea: RecipeIdea) -> some View {
        Button {
            selectedIdea = idea
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(idea.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 230, height: 125)
                    .clipped()
                Text(idea.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Label("\(idea.minutes) min", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 230, alignment: .leading)
            .padding(.bottom, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var planScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeading("Your Week", subtitle: "A simple plan you can edit whenever life changes.")
                weeklyPlanBadge
                ForEach(days, id: \.self) { day in
                    let meal = settings.homeData.weeklyMeals[day]
                    HStack(spacing: 12) {
                        Text(day)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(green)
                            .frame(width: 43, height: 43)
                            .background(green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        TextField("Add a meal", text: Binding(
                            get: { settings.homeData.weeklyMeals[day]?.title ?? "" },
                            set: {
                                var data = settings.homeData
                                data.setMeal($0, for: day)
                                settings.homeData = data
                            }
                        ))
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.words)
                        Button {
                            var data = settings.homeData
                            data.toggleMealLock(for: day)
                            settings.homeData = data
                        } label: {
                            Image(systemName: meal?.isLocked == true ? "lock.fill" : "lock.open")
                                .foregroundStyle(meal?.isLocked == true ? green : .gray)
                        }
                        .disabled(meal == nil)
                        .accessibilityLabel(meal?.isLocked == true ? "Unlock \(day) meal" : "Lock \(day) meal")
                    }
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 15))
                }
                if let maxTime = settings.customizationPreferences.choices["maxTime"]?.first {
                    Label("Your usual cooking limit: \(maxTime)", systemImage: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var recipesScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeading("Recipes", subtitle: "Your saved ideas and recipe links, all in one place.")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search recipes", text: $searchText)
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                Button {
                    activeSheet = .recipeLink
                } label: {
                    Label("Save a recipe link", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(green)
                }
                if !settings.homeData.recipeLinks.isEmpty {
                    sectionTitle("Saved Links")
                    ForEach(settings.homeData.recipeLinks) { recipe in
                        if let url = URL(string: recipe.url) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "link")
                                        .foregroundStyle(green)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(recipe.title)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text(recipe.url)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(ink)
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                            }
                        }
                    }
                }
                if !settings.homeData.savedIdeaIDs.isEmpty {
                    sectionTitle("Saved Ideas")
                    ForEach(RecipeIdea.examples.filter { settings.homeData.savedIdeaIDs.contains($0.id) }) { idea in
                        recipeCard(idea)
                    }
                }
                if settings.homeData.recipeLinks.isEmpty && settings.homeData.savedIdeaIDs.isEmpty {
                    recipeEmptyState
                }
            }
            .padding(20)
        }
    }

    private var moreScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeading("Your Kitchen", subtitle: "The details that make Flavourly yours.")
                HStack(spacing: 14) {
                    Image("HomeEmptyPot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your name")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("Your name", text: Binding(
                            get: { settings.userName },
                            set: { settings.userName = String($0.prefix(40)) }
                        ))
                        .font(.system(size: 18, weight: .semibold))
                        .textInputAutocapitalization(.words)
                    }
                }
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))

                HStack {
                    Image(systemName: settings.isPremium ? "crown.fill" : "sparkles")
                        .foregroundStyle(Color(hex: "#E5A531"))
                    Text(settings.isPremium ? "Premium active" : "Explore Premium")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if !settings.isPremium {
                        Button("View plans") { activeSheet = .premium }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(ink)
                .padding(18)
                .background(Color(hex: "#FFF2D7"), in: RoundedRectangle(cornerRadius: 17))

                Button {
                    settings.customizationStep = 0
                    settings.hasSeenCustomization = false
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Edit food preferences")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
                sectionTitle("Saved for your plan")
                ForEach(["goals", "diet", "allergies", "cuisines", "maxTime", "skill"], id: \.self) { key in
                    let values = settings.customizationPreferences.choices[key] ?? []
                    if !values.isEmpty {
                        HStack(alignment: .top) {
                            Text(key == "maxTime" ? "Cooking time" : key.capitalized)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 105, alignment: .leading)
                            Text(values.joined(separator: ", "))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.plan)
            Button {
                showingAddMenu = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color(hex: "#974AE6"), in: Circle())
                    .shadow(color: Color(hex: "#974AE6").opacity(0.3), radius: 8, y: 3)
            }
            .accessibilityLabel("Add")
            .frame(maxWidth: .infinity)
            .offset(y: -8)
            tabButton(.recipes)
            tabButton(.more)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.white)
        .overlay(alignment: .top) {
            Color.black.opacity(0.07).frame(height: 1)
        }
    }

    private func tabButton(_ tab: HomeTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19))
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? ink : Color(hex: "#778195"))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(ink)
    }

    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .serif))
                .foregroundStyle(ink)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var scannerSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 45))
                .foregroundStyle(Color(hex: "#24ADB5"))
            Text("Food scanning is coming soon")
                .font(.system(size: 22, weight: .semibold))
            Text("You can add meals to your plan and grocery items manually right now.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Grocery List") { activeSheet = .groceries }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .presentationDetents([.medium])
    }
}

private struct GroceryListSheet: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var newItem = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Add an item", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    Button("Add", action: addItem)
                        .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(14)
                .background(Color(hex: "#F2F6EF"), in: RoundedRectangle(cornerRadius: 13))
                .padding(.horizontal)

                List {
                    ForEach(settings.homeData.groceryItems) { item in
                        Button {
                            var data = settings.homeData
                            guard let index = data.groceryItems.firstIndex(where: { $0.id == item.id }) else { return }
                            data.groceryItems[index].isChecked.toggle()
                            settings.homeData = data
                        } label: {
                            Label(item.title, systemImage: item.isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isChecked ? .secondary : Color.primary)
                        }
                    }
                    .onDelete { offsets in
                        var data = settings.homeData
                        data.groceryItems.remove(atOffsets: offsets)
                        settings.homeData = data
                    }
                }
                .overlay {
                    if settings.homeData.groceryItems.isEmpty {
                        ContentUnavailableView("Your list is empty", systemImage: "basket", description: Text("Add an item above to get started."))
                    }
                }
            }
            .navigationTitle("Grocery List")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addItem() {
        var data = settings.homeData
        data.addGroceryItem(newItem)
        settings.homeData = data
        newItem = ""
    }
}

private struct SaveRecipeLinkSheet: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var invalidURL = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Recipe name (optional)", text: $title)
                TextField("https://example.com/recipe", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("This saves the link. Full recipe extraction will be added later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Save Link") {
                    var data = settings.homeData
                    if data.addRecipeLink(title: title, url: url) {
                        settings.homeData = data
                        dismiss()
                    } else {
                        invalidURL = true
                    }
                }
                .disabled(url.isEmpty)
            }
            .navigationTitle("Save Recipe")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Enter a valid web link", isPresented: $invalidURL) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Use a link beginning with http:// or https://.")
            }
        }
    }
}

private struct RecipeIdeaSheet: View {
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    let idea: RecipeIdea

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { geometry in
                        Image(idea.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: 220)
                            .clipped()
                    }
                    .frame(height: 220)
                    Text(idea.title)
                        .font(.system(size: 27, weight: .bold, design: .serif))
                    Label("\(idea.minutes) minutes · \(idea.category)", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Text("Example recipe. Check product labels and ingredients for your own dietary needs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Ingredients")
                        .font(.headline)
                    ForEach(idea.ingredients, id: \.self) { ingredient in
                        Text("• \(ingredient)")
                    }
                    Text("Directions")
                        .font(.headline)
                    ForEach(Array(idea.directions.enumerated()), id: \.offset) { index, direction in
                        Text("\(index + 1). \(direction)")
                    }
                    Button(settings.homeData.savedIdeaIDs.contains(idea.id) ? "Remove from Saved" : "Save Recipe Idea") {
                        var data = settings.homeData
                        data.toggleSavedIdea(idea.id)
                        settings.homeData = data
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#155634"))
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
