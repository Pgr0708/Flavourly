import CoreData
internal import Combine
import Foundation
import UIKit

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
            if let found = Self.foundPhotos[copy.title.lowercased()], copy.imageURL == nil, Self.needsBetterPhoto(copy.imageName) {
                copy.imageURL = found
                copy.imageName = nil
            }
            let recipe = Kitchen.save(copy, in: context, commit: false)
            recipe.isCurated = true
            recipe.isSaved = false
            return recipe
        }
    }

    /// No bundled photo, or one too small to fill a card (several ship at ~100–300 px): look for a sharp one.
    static func needsBetterPhoto(_ imageName: String?) -> Bool {
        guard let imageName, let image = UIImage(named: imageName) else { return true }
        return image.size.width * image.scale < 500
    }

    /// Free photos found for built-in recipes that ship without one, kept so the next launch shows them at once.
    static var foundPhotos: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "libraryPhotos") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "libraryPhotos") }
    }
}
