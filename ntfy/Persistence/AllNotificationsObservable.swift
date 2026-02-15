import CoreData
import SwiftUI

/// Fetches all notifications across all subscriptions, sorted by time descending.
/// Used by the unified notifications view to show a combined timeline.
class AllNotificationsObservable: NSObject, ObservableObject {
    private let tag = "AllNotificationsObservable"

    private lazy var fetchedResultsController: NSFetchedResultsController<Notification> = {
        let fetchRequest: NSFetchRequest<Notification> = Notification.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]

        let controller = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        return controller
    }()

    @Published var notifications: [Notification] = []

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = Store.shared.context) {
        self.context = context
        super.init()

        do {
            Log.d(tag, "Fetching all notifications")
            try self.fetchedResultsController.performFetch()
            self.notifications = self.fetchedResultsController.fetchedObjects ?? []
        } catch {
            Log.w(tag, "Failed to fetch all notifications \(error)")
        }
    }
}

extension AllNotificationsObservable: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async {
            self.notifications = self.fetchedResultsController.fetchedObjects ?? []
        }
    }
}
