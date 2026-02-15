import XCTest
@testable import ntfy

/// Tests for AllNotificationsObservable and search/filter logic
final class UnifiedNotificationsTests: XCTestCase {

    // MARK: - AllNotificationsObservable Tests

    func testAllNotificationsObservableInitialization() {
        let store = Store(inMemory: true)
        let observable = AllNotificationsObservable(context: store.context)
        XCTAssertNotNil(observable)
        XCTAssertEqual(observable.notifications.count, 0)
    }

    func testAllNotificationsObservableFetchesAllTopics() {
        let store = Store(inMemory: true)
        store.context.performAndWait {
            // Create subscriptions on different topics
            let sub1 = store.makeSubscription(store.context, "alerts", [
                Message(id: "1", time: 1000, event: "message", topic: "alerts", message: "Alert 1")
            ])
            let sub2 = store.makeSubscription(store.context, "logs", [
                Message(id: "2", time: 2000, event: "message", topic: "logs", message: "Log 1")
            ])
            _ = sub1
            _ = sub2
            try? store.context.save()
        }

        let observable = AllNotificationsObservable(context: store.context)
        XCTAssertEqual(observable.notifications.count, 2)
    }

    func testAllNotificationsObservableSortedByTimeDescending() {
        let store = Store(inMemory: true)
        store.context.performAndWait {
            store.makeSubscription(store.context, "test", [
                Message(id: "old", time: 1000, event: "message", topic: "test", message: "Old"),
                Message(id: "new", time: 3000, event: "message", topic: "test", message: "New"),
                Message(id: "mid", time: 2000, event: "message", topic: "test", message: "Mid"),
            ])
            try? store.context.save()
        }

        let observable = AllNotificationsObservable(context: store.context)
        XCTAssertEqual(observable.notifications.count, 3)
        // Should be sorted newest first
        XCTAssertEqual(observable.notifications[0].id, "new")
        XCTAssertEqual(observable.notifications[1].id, "mid")
        XCTAssertEqual(observable.notifications[2].id, "old")
    }

    func testAllNotificationsObservableEmptyStore() {
        let store = Store(inMemory: true)
        let observable = AllNotificationsObservable(context: store.context)
        XCTAssertTrue(observable.notifications.isEmpty)
    }

    func testAllNotificationsObservableMultipleServers() {
        let store = Store(inMemory: true)
        store.context.performAndWait {
            // Simulate two different servers
            let sub1 = Subscription(context: store.context)
            sub1.baseUrl = "https://ntfy.sh"
            sub1.topic = "topic1"
            let n1 = store.makeNotification(store.context, Message(id: "1", time: 1000, event: "message", topic: "topic1", message: "From server 1"))
            n1.subscription = sub1

            let sub2 = Subscription(context: store.context)
            sub2.baseUrl = "https://custom.example.com"
            sub2.topic = "topic2"
            let n2 = store.makeNotification(store.context, Message(id: "2", time: 2000, event: "message", topic: "topic2", message: "From server 2"))
            n2.subscription = sub2

            try? store.context.save()
        }

        let observable = AllNotificationsObservable(context: store.context)
        XCTAssertEqual(observable.notifications.count, 2)
    }

    // MARK: - Search/Filter Tests

    func testFilterByMessageContent() {
        let results = filterNotifications(
            query: "alert",
            messages: [
                ("1", "Alert fired", nil, nil),
                ("2", "System log", nil, nil),
                ("3", "Critical alert", nil, nil),
            ]
        )
        XCTAssertEqual(results.count, 2)
    }

    func testFilterByTitle() {
        let results = filterNotifications(
            query: "warning",
            messages: [
                ("1", "Something happened", "Warning Title", nil),
                ("2", "Normal message", nil, nil),
            ]
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "1")
    }

    func testFilterByTags() {
        let results = filterNotifications(
            query: "urgent",
            messages: [
                ("1", "Message", nil, "urgent,important"),
                ("2", "Other", nil, "info"),
            ]
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "1")
    }

    func testFilterCaseInsensitive() {
        let results = filterNotifications(
            query: "ALERT",
            messages: [
                ("1", "alert fired", nil, nil),
                ("2", "Alert Fired", nil, nil),
                ("3", "no match", nil, nil),
            ]
        )
        XCTAssertEqual(results.count, 2)
    }

    func testFilterEmptyQuery() {
        let results = filterNotifications(
            query: "",
            messages: [
                ("1", "Message 1", nil, nil),
                ("2", "Message 2", nil, nil),
            ]
        )
        XCTAssertEqual(results.count, 2)
    }

    func testFilterNoResults() {
        let results = filterNotifications(
            query: "nonexistent",
            messages: [
                ("1", "Hello", nil, nil),
                ("2", "World", nil, nil),
            ]
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testFilterMatchesTitleAndMessage() {
        let results = filterNotifications(
            query: "test",
            messages: [
                ("1", "test message", nil, nil),
                ("2", "other", "test title", nil),
                ("3", "no match here", "no match", nil),
            ]
        )
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Helpers

    /// Simulates the search/filter logic used in NotificationListView
    private func filterNotifications(
        query: String,
        messages: [(id: String, message: String, title: String?, tags: String?)]
    ) -> [TestNotification] {
        let notifications = messages.map { TestNotification(id: $0.id, message: $0.message, title: $0.title, tags: $0.tags) }
        if query.isEmpty { return notifications }
        let q = query.lowercased()
        return notifications.filter { n in
            n.message.lowercased().contains(q) ||
            (n.title?.lowercased().contains(q) ?? false) ||
            (n.tags?.lowercased().contains(q) ?? false)
        }
    }
}

/// Lightweight test double for notification filtering tests (avoids CoreData)
private struct TestNotification {
    let id: String
    let message: String
    let title: String?
    let tags: String?
}
