import CoreData
import SwiftUI

/// Sheets that can open from anywhere (dock quick actions, Home, share inbox).
enum RootSheet: String, Identifiable {
    case importLink, importScan, importText, newRecipe, groceryAdd, notifications, paywall
    var id: String { rawValue }
}

/// A finished import waiting on Review.
struct ReviewItem: Identifiable {
    let id = UUID()
    var draft: RecipeDraft
    var imageData: Data?
}

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var importer = ImportService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .home
    @State private var quickAddOpen = false
    @State private var showCookNow = false
    @State private var sheet: RootSheet?
    @State private var review: ReviewItem?
    @State private var homePath = NavigationPath()
    @State private var cookbookPath = NavigationPath()
    @State private var planPath = NavigationPath()
    @State private var shopPath = NavigationPath()

    /// The dock only belongs on the four tab roots; pushed screens (recipe, planner…) get the full height.
    private var isPushed: Bool {
        switch tab {
        case .home: !homePath.isEmpty
        case .cookbook: !cookbookPath.isEmpty
        case .plan: !planPath.isEmpty
        case .shop: !shopPath.isEmpty
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                NavigationStack(path: $homePath) {
                    HomeView(tab: $tab, sheet: $sheet, showCookNow: $showCookNow).flavourlyDestinations()
                }
                .tag(AppTab.home)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack(path: $cookbookPath) {
                    CookbookView(sheet: $sheet).flavourlyDestinations()
                }
                .tag(AppTab.cookbook)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack(path: $planPath) {
                    PlanView().flavourlyDestinations()
                }
                .tag(AppTab.plan)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack(path: $shopPath) {
                    ShopView(sheet: $sheet).flavourlyDestinations()
                }
                .tag(AppTab.shop)
                .toolbar(.hidden, for: .tabBar)
            }

            if quickAddOpen && !isPushed {
                QuickAddMenu(onSelect: handleQuickAction) {
                    withAnimation(Theme.spring) { quickAddOpen = false }
                }
                .zIndex(1)
            }

            if !isPushed {
                KitchenDock(selection: $tab, quickAddOpen: $quickAddOpen, onCook: { showCookNow = true }, onQuickAction: handleQuickAction)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(Theme.spring, value: isPushed)
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.light)
        .tint(Theme.green)
        .sheet(item: $sheet) { sheet in
            rootSheet(sheet)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showCookNow) {
            CookNowView().environmentObject(settings)
        }
        .fullScreenCover(item: $review) { item in
            ImportReviewView(draft: item.draft, imageData: item.imageData) { _ in review = nil }
                .environmentObject(settings)
        }
        .overlay(alignment: .top) {
            if importer.readyDraft != nil {
                ReadyToast {
                    if let draft = importer.readyDraft {
                        review = ReviewItem(draft: draft, imageData: importer.readyImageData)
                    }
                    importer.readyDraft = nil
                    importer.readyImageData = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: importer.readyDraft != nil)
        .onReceive(NotificationCenter.default.publisher(for: .openReview)) { note in
            if let item = note.object as? ReviewItem { review = item }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { note in
            if let target = note.object as? AppTab { tab = target }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                processSharedInbox()
                Task { await Usage.sync() }
            }
        }
        .task {
            RankContext.skillCap = Difficulty(skill: settings.customizationPreferences.choices["skill"]?.first)
            Kitchen.relearnTaste()
            processSharedInbox()
            Task { await Usage.sync() }
            NotificationService.shared.reschedule()
            if !settings.hasSeenNotificationPrompt {
                try? await Task.sleep(for: .seconds(1.2))
                sheet = .notifications
            }
        }
    }

    @ViewBuilder
    private func rootSheet(_ sheet: RootSheet) -> some View {
        switch sheet {
        case .importLink: ImportView(start: .link)
        case .importScan: ImportView(start: .photo)
        case .importText: ImportView(start: .text)
        case .newRecipe: NavigationStack { RecipeEditorView(recipe: nil) }
        case .groceryAdd: GroceryQuickAddSheet()
        case .notifications: NotificationScreenView()
        case .paywall: PaywallScreenView()
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        withAnimation(Theme.spring) { quickAddOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch action {
            case .link: sheet = .importLink
            case .scan: sheet = .importScan
            case .write: sheet = .newRecipe
            case .grocery: sheet = .groceryAdd
            }
        }
    }

    /// Links shared from Instagram, TikTok, YouTube or Safari via the Share Extension.
    private func processSharedInbox() {
        let items = ImportService.takePendingShares()
        guard let first = items.first, !importer.isRunning else { return }
        Task {
            DropsManager.showProgress(id: "share", title: "Importing shared recipe", fraction: 0.1)
            do {
                let draft = ImportService.normalizedURL(first) != nil && !first.contains("\n")
                    ? try await importer.importLink(first)
                    : try await importer.importText(first)
                DropsManager.showProgress(id: "share", title: "Importing shared recipe", fraction: 1, subtitle: draft.title)
                review = ReviewItem(draft: draft, imageData: nil)
            } catch let failure as ImportService.Failure {
                DropsManager.endProgress(id: "share")
                if let partial = failure.partial {
                    review = ReviewItem(draft: partial, imageData: nil)
                } else if failure.isLimit {
                    sheet = .paywall
                } else {
                    DropsManager.showError(title: failure.title, subtitle: failure.message)
                }
            } catch {
                DropsManager.endProgress(id: "share")
                DropsManager.showError(title: "Import failed", subtitle: error.localizedDescription)
            }
        }
    }
}

/// "Recipe ready to review" pill after a background import.
private struct ReadyToast: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.primary()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.leaf)
                Text("Recipe ready to review").font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Theme.ink, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 8)
    }
}

extension Notification.Name {
    static let openReview = Notification.Name("flavourly.openReview")
    static let switchTab = Notification.Name("flavourly.switchTab")
}

// MARK: - Routes

enum SmartCollection: String, CaseIterable, Hashable {
    case favourites, quick, cookedBefore, notTried, needsReview, archived

    var title: String {
        switch self {
        case .favourites: "Favourites"
        case .quick: "30 minutes or less"
        case .cookedBefore: "Cooked before"
        case .notTried: "Not tried yet"
        case .needsReview: "Needs a check"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .favourites: "heart.fill"
        case .quick: "bolt.fill"
        case .cookedBefore: "checkmark.seal.fill"
        case .notTried: "sparkles"
        case .needsReview: "exclamationmark.triangle.fill"
        case .archived: "archivebox.fill"
        }
    }

    var predicate: NSPredicate {
        switch self {
        case .favourites: NSPredicate(format: "isSaved == YES AND isArchived == NO AND isFavorite == YES")
        case .quick: NSPredicate(format: "isSaved == YES AND isArchived == NO AND totalMinutes > 0 AND totalMinutes <= 30")
        case .cookedBefore: NSPredicate(format: "isSaved == YES AND isArchived == NO AND cookedCount > 0")
        case .notTried: NSPredicate(format: "isSaved == YES AND isArchived == NO AND cookedCount == 0")
        case .needsReview: NSPredicate(format: "isSaved == YES AND isArchived == NO AND needsReview == YES")
        case .archived: NSPredicate(format: "isArchived == YES")
        }
    }
}

enum Route: Hashable {
    case recipe(NSManagedObjectID)
    case library(String)
    case smartCollection(SmartCollection)
    case collection(NSManagedObjectID)
    case discover
    case profile, preferences, household, nutrition, healthConnect, settings
    case member(NSManagedObjectID?)
    case pantry, cookFromPantry
    case plannerSetup
}

struct RouteView: View {
    let route: Route
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        switch route {
        case .recipe(let id):
            if let recipe = try? context.existingObject(with: id) as? Recipe {
                RecipeDetailView(recipe: recipe)
            } else {
                ContentUnavailableView("Recipe not found", systemImage: "book.closed")
            }
        case .library(let remoteID):
            if let recipe = Library.shared.recipe(id: remoteID) {
                RecipeDetailView(recipe: recipe)
            } else {
                ContentUnavailableView("Recipe not found", systemImage: "book.closed")
            }
        case .smartCollection(let smart):
            CollectionView(smart: smart, collection: nil)
        case .collection(let id):
            CollectionView(smart: nil, collection: try? context.existingObject(with: id) as? RecipeCollection)
        case .discover: DiscoverView()
        case .profile: ProfileView()
        case .preferences: PreferencesView()
        case .household: HouseholdView()
        case .member(let id): MemberEditorView(member: id.flatMap { try? context.existingObject(with: $0) as? HouseholdMember })
        case .nutrition: NutritionView()
        case .healthConnect: HealthConnectView()
        case .settings: SettingsView()
        case .pantry: PantryView()
        case .cookFromPantry: CookFromPantryView()
        case .plannerSetup: PlannerView()
        }
    }
}

extension View {
    func flavourlyDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }

    /// Keeps the last row clear of the floating dock.
    func dockSpacing() -> some View {
        safeAreaInset(edge: .bottom) { Color.clear.frame(height: 78) }
    }
}

extension Recipe {
    /// Navigation value that works for both saved and library recipes.
    var route: Route {
        if managedObjectContext === Library.shared.context, let remoteID { return .library(remoteID) }
        return .recipe(objectID)
    }
}
