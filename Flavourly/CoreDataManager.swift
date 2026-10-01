//
//  CoreDataManager.swift
//  Flavourly
//
//  Local-first storage. Syncs through the user's own iCloud when available,
//  so there is no login anywhere in the app.
//

import CoreData

final class CoreDataManager {
    static let shared = CoreDataManager()
    static let cloudContainerID = "iCloud.com.bhavik.Flavourly"

    let container: NSPersistentCloudKitContainer
    /// False only when the on-disk store could not be opened and we fell back to memory.
    private(set) var isPersistent = true

    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentCloudKitContainer(name: "Flavourly")
        // Never delete the user's store on failure — degrade instead:
        // iCloud sync → local only → in memory (and tell the user).
        if !load(cloudKit: true), !load(cloudKit: false) {
            isPersistent = false
            _ = load(cloudKit: false, inMemory: true)
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            DropsManager.showError(title: "Couldn't save", subtitle: error.localizedDescription)
        }
    }

    func delete(_ object: NSManagedObject) {
        context.delete(object)
        save()
    }

    func fetch<T: NSManagedObject>(_ type: T.Type, _ predicate: NSPredicate? = nil, sort: [NSSortDescriptor] = [], limit: Int = 0) -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = predicate
        request.sortDescriptors = sort
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    func count<T: NSManagedObject>(_ type: T.Type, _ predicate: NSPredicate? = nil) -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = predicate
        return (try? context.count(for: request)) ?? 0
    }

    private func load(cloudKit: Bool, inMemory: Bool = false) -> Bool {
        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inMemory { description.url = URL(fileURLWithPath: "/dev/null") }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = cloudKit
            ? NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerID)
            : nil
        container.persistentStoreDescriptions = [description]

        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure {
            print("Core Data store failed to load (cloudKit: \(cloudKit), inMemory: \(inMemory)): \(failure)")
        }
        return failure == nil
    }
}
