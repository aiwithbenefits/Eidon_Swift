import CoreData
import os // For unified logging

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer // Using CloudKit container for potential future-proofing, works locally too.
                                                // Use NSPersistentContainer if CloudKit is definitely not needed.

    // Logger for Core Data specific messages
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon", category: "Persistence")

    init(inMemory: Bool = false) {
        // Use the actual name of your .xcdatamodeld file (e.g., "EidonDataModel")
        // If your model file is named "Eidon.xcdatamodeld", then the name is "Eidon".
        container = NSPersistentCloudKitContainer(name: "Eidon") // Ensure this matches your .xcdatamodeld file name

        if inMemory {
            // For testing: use an in-memory store
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        } else {
            // Production store path
            let storeURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("Eidon.sqlite")
            let description = NSPersistentStoreDescription(url: storeURL)
            
            // Enable persistent history tracking for potential future features like syncing or deduplication
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Optional: Lightweight migrations
            description.shouldInferMappingModelAutomatically = true
            description.shouldMigrateStoreAutomatically = true
            
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // This is a serious error that should be handled appropriately in a production app.
                // For example, display an error to the user, log extensively, or attempt recovery.
                self.logger.critical("Failed to load Core Data persistent store at \(storeDescription.url?.path ?? "unknown URL"): \(error.localizedDescription), \(error.userInfo)")
                // Depending on the error, a fatalError might be too abrupt for a shipping app,
                // but for development it helps identify issues quickly.
                // fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
                self.logger.info("Core Data persistent store loaded successfully from: \(storeDescription.url?.path ?? "in-memory store")")
                
                // Configure the view context
                self.container.viewContext.automaticallyMergesChangesFromParent = true
                self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy // Or another appropriate policy
            }
        }
    }

    // MARK: - Convenience Properties for Contexts
    
    /// The main context, associated with the main queue. Use for UI-related data tasks.
    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    /// Creates a new background context for performing data tasks off the main queue.
    /// Changes made in a background context must be merged back into the viewContext if they need to be reflected in the UI.
    func newBackgroundContext() -> NSManagedObjectContext {
        return container.newBackgroundContext()
    }

    // MARK: - Saving Contexts

    /// Saves the view context if it has changes.
    func saveViewContext() {
        saveContext(context: viewContext)
    }

    /// Saves the given managed object context if it has changes.
    /// - Parameter context: The `NSManagedObjectContext` to save.
    func saveContext(context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
                logger.debug("Context saved successfully.")
            } catch {
                let nsError = error as NSError
                logger.error("Failed to save context: \(nsError.localizedDescription), \(nsError.userInfo)")
                // In a production app, handle this error more gracefully.
                // For development, a fatalError might be useful to catch issues early.
                // fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        } else {
            logger.debug("Context has no changes to save.")
        }
    }

    // MARK: - Preview Provider for SwiftUI Previews (Optional but Recommended)
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        
        // Create some sample data for previews
        for i in 0..<5 {
            let newEntry = EidonEntryEntity(context: context) // Replace with your actual entity name
            newEntry.id = UUID()
            newEntry.timestamp = Date().addingTimeInterval(TimeInterval(-i * 3600)) // Offset by hours
            newEntry.app = "PreviewApp \(i)"
            newEntry.title = "Sample Preview Title \(i)"
            newEntry.text = "This is sample OCR text for preview entry number \(i)."
            newEntry.filename = "preview_image_\(i).png"
            if i % 2 == 0 {
                newEntry.pageURL = "https://example.com/preview/\(i)"
            }
        }
        
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            // Using Logger here as well
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Preview", category: "PersistencePreview")
            logger.error("Failed to save preview context: \(nsError.localizedDescription), \(nsError.userInfo)")
            // fatalError("Unresolved error \(nsError), \(nsError.userInfo)") // Might be too disruptive for previews
        }
        return controller
    }()
}
