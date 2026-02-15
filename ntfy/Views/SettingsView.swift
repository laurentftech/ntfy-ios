import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Delivery Method"),
                    footer: Text("Polling works without Firebase. Use this for self-hosted servers or if you don't want Google dependencies.")
                ) {
                    DeliveryMethodView()
                }
                Section(
                    header: Text("General"),
                    footer: Text("When subscribing to new topics, this server will be selected by default.")
                ) {
                    DefaultServerView()
                }
                Section(
                    header: Text("Servers"),
                    footer: Text("Configure authentication for your ntfy servers. Tap a server to add or edit credentials.")
                ) {
                    NavigationLink(destination: ServerListView()) {
                        HStack {
                            Image(systemName: "server.rack")
                            Text("Manage Servers")
                        }
                    }
                }
                Section(header: Text("About")) {
                    AboutView()
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}


struct DefaultServerView: View {
    @EnvironmentObject private var store: Store
    @State private var selectedServer: String = ""

    var body: some View {
        Picker("Default server", selection: $selectedServer) {
            ForEach(store.getServers(), id: \.self) { server in
                Text(shortUrl(url: server)).tag(server)
            }
        }
        .onAppear {
            selectedServer = store.getDefaultBaseUrl()
        }
        .onChange(of: selectedServer) { newValue in
            if !newValue.isEmpty {
                store.saveDefaultBaseUrl(baseUrl: newValue)
            }
        }
    }
}

// MARK: - Delivery Method View

struct DeliveryMethodView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @AppStorage("usePolling") private var usePolling = false
    @State private var showingAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $usePolling) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Polling")
                        .foregroundColor(.primary)
                    Text(usePolling ? "Polling enabled" : "Firebase push")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .onChange(of: usePolling) { newValue in
                if newValue {
                    // Enable polling
                    appDelegate.usePolling = true
                    appDelegate.startPollingService()
                } else {
                    // Disable polling, use Firebase
                    appDelegate.stopPollingService()
                    appDelegate.usePolling = false
                }
            }
            
            if !usePolling {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                    Text("Firebase (Push)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.orange)
                    Text("Polling (No instant notifications)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct UserTableView: View {
    @EnvironmentObject private var store: Store
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \User.baseUrl, ascending: true)]) var users: FetchedResults<User>
    
    @State private var selectedUser: User?
    @State private var showDialog = false
    
    @State private var baseUrl: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    
    var body: some View {
        let _ = selectedUser?.username // Workaround for FB7823148, see https://developer.apple.com/forums/thread/652080
        List {
            ForEach(users) { user in
                Button(action: {
                    selectedUser = user
                    baseUrl = user.baseUrl ?? "?"
                    username = user.username ?? "?"
                    showDialog = true
                }) {
                    UserRowView(user: user)
                        .foregroundColor(.primary)
                }
            }
            Button(action: {
                showDialog = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add user")
                }
                .foregroundColor(.primary)
            }
            .padding(.all, 4)
        }
        .sheet(isPresented: $showDialog) {
            NavigationView {
                Form {
                    Section(
                        footer: (selectedUser == nil)
                        ? Text("You can add a user here. All topics for the given server will use this user.")
                        : Text("Edit the username or password for \(shortUrl(url: baseUrl)) here. This user is used for all topics of this server. Leave the password blank to leave it unchanged.")
                    ) {
                        if selectedUser == nil {
                            TextField("Service URL, e.g. https://ntfy.home.io", text: $baseUrl)
                                .disableAutocapitalization()
                                .disableAutocorrection(true)
                        }
                        TextField("Username", text: $username)
                            .disableAutocapitalization()
                            .disableAutocorrection(true)
                        SecureField("Password", text: $password)
                    }
                }
                .navigationTitle(selectedUser == nil ? "Add user" : "Edit user")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if selectedUser == nil {
                            Button("Cancel") {
                                cancelAction()
                            }
                        } else {
                            Menu {
                                Button("Cancel") {
                                    cancelAction()
                                }
                                if #available(iOS 15.0, *) {
                                    Button(role: .destructive) {
                                        deleteAction()
                                    } label: {
                                        Text("Delete")
                                    }
                                } else {
                                    Button("Delete") {
                                        deleteAction()
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .padding([.leading], 40)
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: saveAction) {
                            Text("Save")
                        }
                        .disabled(!isValid())
                    }
                }
            }
        }
    }
    
    private func saveAction() {
        var password = password
        if let user = selectedUser, password == "" {
            password = user.password ?? "?" // If password is blank, leave unchanged
        }
        store.saveUser(baseUrl: baseUrl, username: username, password: password)
        resetAndHide()
    }
    
    private func cancelAction() {
        resetAndHide()
    }
    
    private func deleteAction() {
        store.delete(user: selectedUser!)
        resetAndHide()
    }
    
    private func isValid() -> Bool {
        if selectedUser == nil { // New user
            if baseUrl.range(of: "^https?://.+", options: .regularExpression, range: nil, locale: nil) == nil {
                return false
            } else if username.isEmpty || password.isEmpty {
                return false
            } else if store.getUser(baseUrl: baseUrl) != nil {
                return false
            }
        } else { // Existing user
            if username.isEmpty {
                return false
            }
        }
        return true
    }
    
    private func resetAndHide() {
        showDialog = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Hide first and then reset, otherwise we'll see the text fields change
            selectedUser = nil
            baseUrl = ""
            username = ""
            password = ""
        }
    }
}

struct UserRowView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var user: User
    
    var body: some View {
        // I tried to add a swipe action here to delete, but for some strange reason it doesn't work,
        // even though in the subscription list it does.
        
        HStack {
            Image(systemName: "person.fill")
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(user.username ?? "?")
                    Text(user.baseUrl ?? "?")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.system(size: 12.0))
                .foregroundColor(.gray)
        }
        .padding(.all, 4)
    }
}

struct AboutView: View {
    var body: some View {
        Group {
            Button(action: {
                open(url: "https://ntfy.sh/docs")
            }) {
                HStack {
                    Text("Read the docs")
                    Spacer()
                    Text("ntfy.sh/docs")
                        .foregroundColor(.gray)
                    Image(systemName: "link")
                }
            }
            Button(action: {
                open(url: "https://github.com/binwiederhier/ntfy/issues")
            }) {
                HStack {
                    Text("Report a bug")
                    Spacer()
                    Text("github.com")
                        .foregroundColor(.gray)
                    Image(systemName: "link")
                }
            }
            Button(action: {
                open(url: "itms-apps://itunes.apple.com/app/id1625396347")
            }) {
                HStack {
                    Text("Rate the app")
                    Spacer()
                    Text("App Store")
                        .foregroundColor(.gray)
                    Image(systemName: "star.fill")
                }
            }
            HStack {
                Text("Version")
                Spacer()
                Text("ntfy \(Config.version) (\(Config.build))")
                    .foregroundColor(.gray)
            }
        }
        .foregroundColor(.primary)
    }
    
    private func open(url: String) {
        guard let url = URL(string: url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let store = Store.preview // Store.previewEmpty
        SettingsView()
            .environment(\.managedObjectContext, store.context)
            .environmentObject(store)
            .environmentObject(AppDelegate())
    }
}
