import SwiftUI
import CoreData
import FirebaseMessaging
import UserNotifications

struct SubscriptionListView: View {
    let tag = "SubscriptionList"
    
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appDelegate: AppDelegate
    @ObservedObject var subscriptionsModel = SubscriptionsObservable()
    @State private var showingAddDialog = false
    
    private var subscriptionManager: SubscriptionManager {
        return SubscriptionManager(store: store)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 15.0, *) {
                    subscriptionList
                        .refreshable {
                            subscriptionsModel.subscriptions.forEach { subscription in
                                subscriptionManager.poll(subscription)
                            }
                        }
                } else {
                    subscriptionList
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    subscriptionsModel.subscriptions.forEach { subscription in
                                        subscriptionManager.poll(subscription)
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                        }
                }
            }
            .navigationDestination(for: String.self) { baseUrl in
                if let subscription = subscriptionsModel.subscriptions.first(where: { $0.urlString() == baseUrl }) {
                    NotificationListView(subscription: subscription)
                }
            }
        }
    }
    
    private var subscriptionList: some View {
        List {
            ForEach(subscriptionsModel.subscriptions) { subscription in
                SubscriptionItemNavView(subscription: subscription)
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Subscribed topics")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    self.showingAddDialog = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay(Group {
            if subscriptionsModel.subscriptions.isEmpty {
                VStack {
                    Text("It looks like you don't have any subscriptions yet")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)

                    if #available(iOS 15.0, *) {
                        Text("Click the + to create or subscribe to a topic. Afterwards, you receive notifications on your device when sending messages via PUT or POST.\n\nDetailed instructions are available on [ntfy.sh](https://ntfy.sh) and [in the docs](https://ntfy.sh/docs).")
                            .foregroundColor(.gray)
                    } else {
                        Text("Click the + to create or subscribe to a topic. Afterwards, you receive notifications on your device when sending messages via PUT or POST.\n\nDetailed instructions are available on https://ntfy.sh and https://ntfy.sh/docs")
                            .foregroundColor(.gray)
                    }
                }
                .padding(40)
            }
        })
        .sheet(isPresented: $showingAddDialog) {
            SubscriptionAddView(isShowing: $showingAddDialog)
        }
    }
}

struct SubscriptionItemNavView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var delegate: AppDelegate
    @ObservedObject var subscription: Subscription
    @State private var unsubscribeAlert = false
    
    private var subscriptionManager: SubscriptionManager {
        return SubscriptionManager(store: store)
    }
    
    var body: some View {
        if #available(iOS 15.0, *) {
            subscriptionRow
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        self.unsubscribeAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash.circle")
                    }
                }
        } else {
            subscriptionRow
        }
    }
    
    private var subscriptionRow: some View {
        ZStack {
            NavigationLink(value: subscription.urlString()) {
                EmptyView()
            }
            .opacity(0.0)
            .buttonStyle(PlainButtonStyle())
            
            SubscriptionItemRowView(subscription: subscription)
        }
        .alert(isPresented: $unsubscribeAlert) {
            Alert(
                title: Text("Unsubscribe"),
                message: Text("Do you really want to unsubscribe from this topic and delete all of the notifications you received?"),
                primaryButton: .destructive(
                    Text("Unsubscribe"),
                    action: {
                        self.subscriptionManager.unsubscribe(subscription)
                        self.unsubscribeAlert = false
                    }
                ),
                secondaryButton: .cancel()
            )
        }
    }
}

struct SubscriptionItemRowView: View {
    @ObservedObject var subscription: Subscription
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        let totalNotificationCount = subscription.notificationCount()
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Connection status indicator
                connectionStatusIndicator
                    
                Text(subscription.displayName())
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                Spacer()
                Text(subscription.lastNotification()?.shortDateTime() ?? "")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12.0))
                    .foregroundColor(.gray)
            }
            Spacer()
            Text("\(totalNotificationCount) notification\(totalNotificationCount != 1 ? "s" : "")")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.all, 4)
    }
    
    @ViewBuilder
    private var connectionStatusIndicator: some View {
        // Default to disconnected for now - polling integration to be completed
        let state: ConnectionState = .disconnected
        
        Circle()
            .fill(connectionColor(for: state))
            .frame(width: 10, height: 10)
            .padding(.trailing, 6)
            .help(state.rawValue)
    }
    
    private func connectionColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected:
            return Color.green
        case .connecting:
            return Color.orange
        case .disconnected:
            return Color.red
        }
    }
}

struct SubscriptionListView_Previews: PreviewProvider {
    static var previews: some View {
        let store = Store.preview // Store.previewEmpty
        SubscriptionListView()
            .environment(\.managedObjectContext, store.context)
            .environmentObject(store)
            .environmentObject(AppDelegate())
    }
}
