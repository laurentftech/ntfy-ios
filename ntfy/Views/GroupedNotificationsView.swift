import SwiftUI
import CoreData

enum NotificationReadFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
}

/// Groups notifications by subscription with collapsible sections.
struct GroupedNotificationsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appDelegate: AppDelegate
    @ObservedObject var allNotificationsModel: AllNotificationsObservable

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Subscription.topic, ascending: true)]) var subscriptions: FetchedResults<Subscription>

    @Binding var searchText: String
    @Binding var isSearching: Bool
    @State private var showCopiedToast = false
    @State private var readFilter: NotificationReadFilter = .all

    /// Groups notifications by subscription, sorted by most recent notification time
    private var groupedNotifications: [(subscription: Subscription, notifications: [Notification], unreadCount: Int)] {
        let filtered = filteredNotifications

        // Group by subscription
        var grouped: [NSManagedObjectID: [Notification]] = [:]
        for notification in filtered {
            if let subscription = notification.subscription {
                let id = subscription.objectID
                if grouped[id] == nil {
                    grouped[id] = []
                }
                grouped[id]?.append(notification)
            }
        }

        // Sort groups by most recent notification time (descending)
        // Topics with notifications first, then empty topics
        return subscriptions.map { subscription -> (subscription: Subscription, notifications: [Notification], unreadCount: Int) in
            let notifications = grouped[subscription.objectID] ?? []
            let unreadCount = notifications.filter { !$0.seen }.count
            return (subscription: subscription, notifications: notifications, unreadCount: unreadCount)
        }.sorted { first, second in
            let firstTime = first.notifications.first?.time ?? 0
            let secondTime = second.notifications.first?.time ?? 0
            return firstTime > secondTime
        }
    }

    private var filteredNotifications: [Notification] {
        var notifications = allNotificationsModel.notifications
        
        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            notifications = notifications.filter { notification in
                (notification.message?.lowercased().contains(query) ?? false) ||
                (notification.title?.lowercased().contains(query) ?? false) ||
                (notification.tags?.lowercased().contains(query) ?? false)
            }
        }
        
        // Apply read/unread filter
        switch readFilter {
        case .all:
            return notifications
        case .unread:
            return notifications.filter { !$0.seen }
        }
    }

    var body: some View {
        groupedList
    }

    private var groupedList: some View {
        List {
            if isSearching {
                TextField("Search notifications", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .listRowSeparator(.hidden)
            }
            // Filter picker for read/unread
            Picker("Filter", selection: $readFilter) {
                ForEach(NotificationReadFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .listRowSeparator(.hidden)
            ForEach(groupedNotifications, id: \.subscription.objectID) { group in
                NavigationLink(destination: NotificationListView(subscription: group.subscription).environmentObject(store).environmentObject(appDelegate)) {
                    HStack {
                        Text(group.subscription.displayName())
                            .font(.headline)
                        Spacer()
                        if group.notifications.isEmpty {
                            Text("No notifications")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            if group.unreadCount > 0 {
                                Text("\(group.unreadCount)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            Text("(\(group.notifications.count))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .overlay(Group {
            if subscriptions.isEmpty {
                VStack {
                    Text("No subscriptions yet")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    Text("Add a subscription using the + button, then send a notification to see it here.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            }
        })
        .overlay(
            Group {
                if showCopiedToast {
                    Text("Copied")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray4))
                        .cornerRadius(8)
                        .transition(.opacity)
                }
            },
            alignment: .bottom
        )
    }
}

struct GroupedNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        let store = Store.preview
        let model = AllNotificationsObservable(context: store.context)
        GroupedNotificationsView(allNotificationsModel: model, searchText: .constant(""), isSearching: .constant(false))
            .environment(\.managedObjectContext, store.context)
            .environmentObject(store)
    }
}
