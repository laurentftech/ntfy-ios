import CoreData
import SwiftUI
import UserNotifications

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
    @Published var unreadCount: Int = 0

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = Store.shared.context) {
        self.context = context
        super.init()

        do {
            Log.d(tag, "Fetching all notifications")
            try self.fetchedResultsController.performFetch()
            self.notifications = self.fetchedResultsController.fetchedObjects ?? []
            self.updateUnreadCount()
        } catch {
            Log.w(tag, "Failed to fetch all notifications \(error)")
        }
    }

    private func updateUnreadCount() {
        let count = notifications.filter { !$0.seen }.count
        unreadCount = count
        updateAppBadge(count)
    }

    private func updateAppBadge(_ count: Int) {
        Log.d(tag, "Setting app badge count to \(count)")
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error = error {
                    Log.e(self.tag, "Failed to set badge count", error)
                }
            }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
}

extension AllNotificationsObservable: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async {
            self.notifications = self.fetchedResultsController.fetchedObjects ?? []
            self.updateUnreadCount()
        }
    }
}
