import SwiftUI

/// Flat list of all notifications across all subscriptions, sorted by time descending.
/// Each row shows a topic badge so the user knows which subscription it belongs to.
struct RecentNotificationsView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var allNotificationsModel: AllNotificationsObservable

    @Binding var searchText: String
    @Binding var isSearching: Bool
    @State private var showCopiedToast = false
    @State private var readFilter: NotificationReadFilter = .all

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
        recentList
    }

    private var recentList: some View {
        List {
            if isSearching {
                TextField("Search notifications", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .listRowSeparator(.hidden)
            }
            // Filter picker for read/unread
            if #available(iOS 15.0, *) {
                Picker("Filter", selection: $readFilter) {
                    ForEach(NotificationReadFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .listRowSeparator(.hidden)
            }
            ForEach(filteredNotifications, id: \.self) { notification in
                NotificationRowView(notification: notification, showCopiedToast: $showCopiedToast, showTopicBadge: true)
            }
        }
        .listStyle(PlainListStyle())
        .overlay(Group {
            if allNotificationsModel.notifications.isEmpty {
                VStack {
                    Text("No notifications yet")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    Text("Subscribe to a topic using the + button, then send a notification to see it here.")
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
