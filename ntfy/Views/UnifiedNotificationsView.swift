import SwiftUI

enum NotificationViewMode: String, CaseIterable {
    case recent = "Recent"
    case byTopic = "By Topic"
}

struct UnifiedNotificationsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appDelegate: AppDelegate
    @ObservedObject var subscriptionsModel = SubscriptionsObservable()

    @State private var viewMode: NotificationViewMode = .recent
    @State private var showingAddDialog = false
    @State private var searchText = ""
    @State private var isSearching = false

    @ObservedObject var allNotificationsModel: AllNotificationsObservable

    private var subscriptionManager: SubscriptionManager {
        return SubscriptionManager(store: store)
    }

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $viewMode) {
                            ForEach(NotificationViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation {
                                isSearching.toggle()
                                if !isSearching { searchText = "" }
                            }
                        } label: {
                            Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            self.showingAddDialog = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAddDialog) {
                    SubscriptionAddView(isShowing: $showingAddDialog)
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .recent:
            if #available(iOS 15.0, *) {
                RecentNotificationsView(allNotificationsModel: allNotificationsModel, searchText: $searchText, isSearching: $isSearching)
                    .refreshable {
                        subscriptionsModel.subscriptions.forEach { subscription in
                            subscriptionManager.poll(subscription)
                        }
                    }
            } else {
                RecentNotificationsView(allNotificationsModel: allNotificationsModel, searchText: $searchText, isSearching: $isSearching)
            }
        case .byTopic:
            if #available(iOS 15.0, *) {
                GroupedNotificationsView(allNotificationsModel: allNotificationsModel, searchText: $searchText, isSearching: $isSearching)
                    .refreshable {
                        subscriptionsModel.subscriptions.forEach { subscription in
                            subscriptionManager.poll(subscription)
                        }
                    }
            } else {
                GroupedNotificationsView(allNotificationsModel: allNotificationsModel, searchText: $searchText, isSearching: $isSearching)
            }
        }
    }

}

struct UnifiedNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        let store = Store.preview
        UnifiedNotificationsView(allNotificationsModel: AllNotificationsObservable(context: store.context))
            .environment(\.managedObjectContext, store.context)
            .environmentObject(store)
            .environmentObject(AppDelegate())
    }
}
