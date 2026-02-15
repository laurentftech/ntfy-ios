import UIKit
import SafariServices
import UserNotifications
import Firebase
import FirebaseCore
import FirebaseMessaging
import CoreData

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    private let tag = "AppDelegate"
    private let pollTopic = "~poll" // See ntfy server if ever changed
    
    // Badge count tracking (no longer using a local counter)
    
    // Implements navigation from notifications, see https://stackoverflow.com/a/70731861/1440785
    @Published var selectedBaseUrl: String? = nil
    
    // MARK: - Polling Service (Alternative to Firebase)
    
    /// Polling service for receiving notifications without Firebase
    private(set) var pollingService: PollingService?
    
    /// Whether to use polling instead of Firebase
    /// Set to true if Firebase is not configured or user prefers polling
    var usePolling: Bool = false
    
    /// Start the polling service
    func startPollingService() {
        guard usePolling else { return }
        
        let store = Store.shared
        guard let subscriptions = store.getSubscriptions(), !subscriptions.isEmpty else {
            Log.d(tag, "No subscriptions to poll")
            return
        }
        
        pollingService = PollingService(store: store)
        pollingService?.delegate = self
        pollingService?.startPolling(subscriptions: subscriptions)
        Log.d(tag, "Started polling service for \(subscriptions.count) subscriptions")
    }
    
    /// Stop the polling service
    func stopPollingService() {
        pollingService?.stopPolling()
        pollingService = nil
        Log.d(tag, "Stopped polling service")
    }
    
    /// Register default notification categories with placeholder for ntfy actions
    /// Categories must be registered at app launch, not when showing notifications
    private func registerDefaultNotificationCategories() {
        // Register a placeholder category for ntfy actions
        // The actual actions will be set when the notification is created
        let placeholderAction = UNNotificationAction(
            identifier: "ntfy-action-placeholder",
            title: " ",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "ntfyActions",
            actions: [placeholderAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        Log.d(tag, "Registered default notification categories")
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Log.d(tag, "Launching AppDelegate")

        // Try to configure Firebase - may fail with dummy plist
        // App will still work with polling mode
        configureFirebaseIfAvailable()

        // Register app permissions for push notifications
        UNUserNotificationCenter.current().delegate = self
        
        // Register default notification categories (needed for actions)
        registerDefaultNotificationCategories()
        
        // Only setup Firebase Messaging if Firebase is configured
        if FirebaseApp.app() != nil {
            Messaging.messaging().delegate = self
        } else {
            // No Firebase - enable polling automatically
            Log.d(tag, "No Firebase - enabling polling mode")
            usePolling = true
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            guard success else {
                Log.e(self.tag, "Failed to register for local push notifications", error)
                return
            }
            Log.d(self.tag, "Successfully registered for local push notifications")
        }
        
        // Register too receive remote notifications
        application.registerForRemoteNotifications()
                
        return true
    }
    
    /// Configure Firebase if valid GoogleService-Info.plist exists
    private func configureFirebaseIfAvailable() {
        // Check if we're using a real Firebase config
        guard let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: plistPath),
              let clientId = plist["CLIENT_ID"] as? String,
              !clientId.contains("dummy") else {
            Log.w(tag, "No valid Firebase config found - running in polling-only mode")
            return
        }
        
        FirebaseApp.configure()
        FirebaseConfiguration.shared.setLoggerLevel(.max)
        Log.i(tag, "Firebase configured successfully")
    }
    
    /// Executed when a background notification arrives on the "~poll" topic. This is used to trigger polling of local topics.
    /// See https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/pushing_background_updates_to_your_app
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Log.d(tag, "Background notification received", userInfo)
        
        // Exit out early if this message is not expected
        let topic = userInfo["topic"] as? String ?? ""
        if topic != pollTopic {
            completionHandler(.noData)
            return
        }

        // Poll and show new messages as notifications
        let store = Store.shared
        let subscriptionManager = SubscriptionManager(store: store)
        store.getSubscriptions()?.forEach { subscription in
            subscriptionManager.poll(subscription) { messages in
                messages.forEach { message in
                    self.showNotification(subscription, message)
                }
            }
        }
        completionHandler(.newData)
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Skip if Firebase is not configured
        guard FirebaseApp.app() != nil else {
            Log.d(tag, "Firebase not configured, skipping APNs token registration")
            return
        }
        
        let token = deviceToken.map { data in String(format: "%02.2hhx", data) }.joined()
        Messaging.messaging().apnsToken = deviceToken
        Log.d(tag, "Registered for remote notifications. Passing APNs token to Firebase: \(token)")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.e(tag, "Failed to register for remote notifications", error)
    }
    
    /// Update app icon badge with actual unread count from Core Data.
    /// Uses Swift filtering to match AllNotificationsObservable's logic.
    func updateBadgeCount() {
        let store = Store.shared
        let fetchRequest: NSFetchRequest<Notification> = Notification.fetchRequest()
        do {
            let all = try store.context.fetch(fetchRequest)
            let unreadCount = all.filter { !$0.seen }.count
            Log.d(tag, "Setting badge count to \(unreadCount)")
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(unreadCount) { error in
                    if let error = error {
                        Log.e(self.tag, "Failed to set badge count", error)
                    }
                }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = unreadCount
            }
        } catch {
            Log.e(tag, "Failed to fetch unread count for badge", error)
        }
    }
    
    /// Create a local notification manually (as opposed to a remote notification being generated by Firebase). We need to make the
    /// local notification look exactly like the remote one (same userInfo), so that when we tap it, the userNotificationCenter(didReceive) function
    /// has the same information available.
    private func showNotification(_ subscription: Subscription, _ message: Message) {
        let content = UNMutableNotificationContent()
        content.modify(message: message, baseUrl: subscription.baseUrl ?? "?")
    
        let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil /* now */)
        UNUserNotificationCenter.current().add(request) { (error) in
            if let error = error {
                Log.e(self.tag, "Unable to create notification", error)
            } else {
                // Update badge count after showing notification
                self.updateBadgeCount()
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Executed when the app is in the foreground. Nothing has to be done here, except call the completionHandler.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Log.d(tag, "Notification received via userNotificationCenter(willPresent)", userInfo)
        // Don't clear badge when showing notification in foreground
        // Badge is managed by SubscriptionManager when polling receives messages
        completionHandler([[.banner, .sound]])
    }
    
    /// Executed when the user clicks on the notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Log.d(tag, "Notification received via userNotificationCenter(didReceive)", userInfo)
        Log.d(tag, "Action identifier: \(response.actionIdentifier)")
        guard let message = Message.from(userInfo: userInfo) else {
            Log.w(tag, "Cannot convert userInfo to message", userInfo)
            completionHandler()
            return
        }
        
        Log.d(tag, "Message actions: \(String(describing: message.actions))")
        
        let baseUrl = userInfo["base_url"] as? String ?? Config.appBaseUrl
        let action = message.actions?.first { $0.id == response.actionIdentifier }
        Log.d(tag, "Matched action: \(String(describing: action))")
        
        // Show current topic
        if message.topic != "" {
            selectedBaseUrl = topicUrl(baseUrl: baseUrl, topic: message.topic)
        }
        
        // Execute user action or click action (if any)
        if let action = action {
            ActionExecutor.execute(action)
        } else if let click = message.click, click != "", let url = URL(string: click) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        // Update badge when user interacts with notification
        updateBadgeCount()
    
        completionHandler()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Skip if Firebase is not configured
        guard FirebaseApp.app() != nil else {
            Log.d(tag, "Firebase not configured, skipping FCM token handling")
            return
        }
        
        Log.d(tag, "Firebase token received: \(String(describing: fcmToken))")
        
        // Subscribe to ~poll topic
        Messaging.messaging().subscribe(toTopic: pollTopic)
        
        // Re-subscribe to Firebase for all topics
        let store = Store.shared
        store.getSubscriptions()?.forEach{ subscription in
            if let baseUrl = subscription.baseUrl, let topic = subscription.topic {
                Log.d(tag, "Re-subscribing to topic \(baseUrl)/\(topic)")
                if baseUrl == Config.appBaseUrl {
                    Messaging.messaging().subscribe(toTopic: topic)
                } else {
                    Messaging.messaging().subscribe(toTopic: topicHash(baseUrl: baseUrl, topic: topic))
                }
            }
        }
    }
}

// MARK: - PollingServiceDelegate

extension AppDelegate: PollingServiceDelegate {
    func pollingService(_ service: PollingService, didReceiveMessage message: Message, for subscription: Subscription) {
        Log.d(tag, "Received message via polling: \(message.id)")
        
        // Store the message
        let store = Store.shared
        store.save(notificationFromMessage: message, withSubscription: subscription)
        
        // Show notification
        showNotification(subscription, message)
    }
}
