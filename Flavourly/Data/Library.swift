import CoreData
internal import Combine
import Foundation

/// Hand-written recipes shipped with the app so Discover is never empty.
/// They live in an in-memory store (never synced) until the user saves or plans one.
@MainActor
final class Library {
    static let shared = Library()

    let context: NSManagedObjectContext
    private(set) var recipes: [Recipe] = []

    private init() {
        let container = NSPersistentContainer(name: "Flavourly", managedObjectModel: CoreDataManager.shared.container.managedObjectModel)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { print("Library store failed: \(error)") }
        }
        context = container.viewContext
        load()
    }

    func recipe(id: String) -> Recipe? { recipes.first { $0.remoteID == id } }

    /// Adds (or refreshes, e.g. once a photo exists) dishes that arrived from the server.
    func add(_ drafts: [RecipeDraft]) -> [Recipe] {
        drafts.compactMap { draft in
            guard let id = draft.remoteID else { return nil }
            var copy = draft
            copy.method = "local"
            let existing = recipe(id: id)
            existing?.objectWillChange.send() // unsaved in-memory edits don't notify views on their own
            let recipe = Kitchen.save(copy, into: existing, in: context, commit: false)
            if existing == nil {
                recipe.isCurated = true
                recipe.isSaved = false
                recipes.append(recipe)
            }
            return recipe
        }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "CuratedRecipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let drafts = try? JSONDecoder().decode([RecipeDraft].self, from: data) else {
            print("CuratedRecipes.json missing or invalid")
            return
        }
        recipes = drafts.map { draft in
            var copy = draft
            copy.method = "library"
            let recipe = Kitchen.save(copy, in: context, commit: false)
            recipe.isCurated = true
            recipe.isSaved = false
            return recipe
        }
    }
}
