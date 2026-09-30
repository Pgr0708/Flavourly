//
//  CoreDataManager.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import Foundation
import CoreData
import SwiftUI

class CoreDataManager: NSObject {
    private(set) var nsPersistentContainer: NSPersistentCloudKitContainer!
    private var hasRetried = false
    
        static let shared = CoreDataManager()
    
    var context: NSManagedObjectContext {
        return CoreDataManager.shared.nsPersistentContainer.viewContext
    }
    
    func delete(_ object: NSManagedObject) {
        context.delete(object)
        save()
    }
    
    func fetchObjectById(id: NSManagedObjectID) -> NSManagedObject? {
        do {
            return try CoreDataManager.shared.context.existingObject(with: id)
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
    
    func save() {
        guard context.hasChanges else {
            print("💾 CoreData: No changes to save.")
            return
        }
        do {
            try context.save()
            print("💾 CoreData SUCCESS: Saved context changes locally.")
        } catch {
            context.rollback()
            print("💾 CoreData ERROR: Failed to save context: \(error.localizedDescription)")
        }
    }
    
    private override init() {
        super.init()
        
        // Listen to CloudKit syncing setup, upload, and download event state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudKitEventChanged(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil
        )
        
        setupContainer()
    }
    
    private func setupContainer() {
        let container = NSPersistentCloudKitContainer(name: "GoViral")
        let storeDescription = container.persistentStoreDescriptions.first
        storeDescription?.shouldMigrateStoreAutomatically = true
        storeDescription?.shouldInferMappingModelAutomatically = true
        
        container.loadPersistentStores { [weak self] description, error in
            guard let self = self else { return }
            
            if error != nil {
//                print("💾 CoreData ERROR: Failed to load CloudKit store...")
                
                if !self.hasRetried {
                    self.hasRetried = true
                    
                    // Delete incompatible database files
                    if let url = storeDescription?.url {
                        let fileManager = FileManager.default
//                        print("💾 CoreData: Deleting incompatible database at \(url.path)")
                        let extensions = ["", "-shm", "-wal"]
                        let base = url.deletingPathExtension()
                        for ext in extensions {
                            let target = base.appendingPathExtension("sqlite\(ext)")
                            if fileManager.fileExists(atPath: target.path) {
                                try? fileManager.removeItem(at: target)
                            }
                        }
                    }
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.setupContainer()
                    }
                    return
                }
                
//                print("💾 CoreData FALLBACK: Loading local NSPersistentContainer without CloudKit sync...")
                let localContainer = NSPersistentCloudKitContainer(name: "SubSync")
                if let localDesc = localContainer.persistentStoreDescriptions.first {
                    localDesc.cloudKitContainerOptions = nil
                }
                localContainer.loadPersistentStores { _, _ in }
                
                self.nsPersistentContainer = localContainer
                localContainer.viewContext.automaticallyMergesChangesFromParent = true
                localContainer.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
                return
            }
            
            // Success – assign only on clean load
            self.nsPersistentContainer = container
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            print("💾 CoreData SUCCESS: Database loaded successfully.")
            
        }
    }
    
    @objc private func cloudKitEventChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              userInfo[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] is NSPersistentCloudKitContainer.Event else {
            return
        }
        
//        let typeStr: String
//        switch event.type {
//        case .setup: typeStr = "Setup"
//        case .import: typeStr = "Import (Download from iCloud)"
//        case .export: typeStr = "Export (Upload to iCloud)"
//        @unknown default: typeStr = "Unknown"
//        }
//
//        if event.succeeded {
//            print("☁️ iCloud CloudKit SUCCESS: \(typeStr) completed successfully.")
//        } else if let error = event.error {
//            print("☁️ iCloud CloudKit ERROR: \(typeStr) failed: \(error.localizedDescription)")
//        } else {
//            print("☁️ iCloud CloudKit ACTIVE: \(typeStr) is in progress...")
//        }
    }
}
