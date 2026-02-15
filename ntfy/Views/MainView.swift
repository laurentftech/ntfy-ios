import Foundation
import SwiftUI

struct MainView: View {
    @StateObject private var allNotificationsModel = AllNotificationsObservable()

    var body: some View {
        TabView {
            UnifiedNotificationsView(allNotificationsModel: allNotificationsModel)
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("Notifications")
                }
                .badge(allNotificationsModel.unreadCount)
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        let store = Store.preview // Store.previewEmpty
        MainView()
            .environment(\.managedObjectContext, store.context)
            .environmentObject(store)
            .environmentObject(AppDelegate())
    }
}
