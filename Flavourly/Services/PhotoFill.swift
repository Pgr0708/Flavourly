import CoreData
import Foundation
internal import Combine

/// Finds a free, credited photo for any recipe card the moment it's shown without one (or with a tiny
/// bundled one), a few at a time — instead of waiting for the server's background painter.
@MainActor
final class PhotoFill: ObservableObject {
    static let shared = PhotoFill()

    /// Bumped when a photo arrives, so every RecipeImage on screen refreshes.
    @Published private(set) var version = 0

    private var tried: Set<String> = []
    private var queue: [Recipe] = []
    private var running = 0

    func request(_ recipe: Recipe) {
        guard recipe.imageURL == nil, recipe.imageData == nil, Library.needsBetterPhoto(recipe.imageName) else { return }
        let title = recipe.displayTitle
        guard title != "Untitled recipe", tried.insert(title.lowercased()).inserted else { return }
        queue.append(recipe)
        pump()
    }

    private func pump() {
        while running < 4, !queue.isEmpty {
            let recipe = queue.removeFirst()
            running += 1
            Task {
                defer {
                    running -= 1
                    pump()
                }
                guard let url = await WorldKitchens.photo(of: recipe.displayTitle),
                      !recipe.isDeleted, recipe.imageURL == nil, recipe.imageData == nil else { return }
                recipe.objectWillChange.send()
                recipe.imageURL = url
                if recipe.isSaved {
                    Kitchen.save()
                } else {
                    recipe.imageName = nil // a sharp web photo replaces a tiny bundled one
                    Library.foundPhotos[recipe.displayTitle.lowercased()] = url
                }
                version += 1
            }
        }
    }
}
