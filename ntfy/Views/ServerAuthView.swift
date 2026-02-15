import SwiftUI
import CoreData

/// Authentication type for server
enum AuthType: String, CaseIterable {
    case none = "None"
    case basic = "Username/Password"
    case token = "Access Token"
}

/// View for configuring server authentication (username/password or token)
struct ServerAuthView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode
    
    let baseUrl: String
    let existingUser: User?
    
    @State private var authType: AuthType = .none
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var token: String = ""
    @State private var showSaveSuccess = false
    @State private var testResult: String? = nil
    @State private var testInProgress = false
    
    init(baseUrl: String, existingUser: User? = nil) {
        self.baseUrl = baseUrl
        self.existingUser = existingUser
    }
    
    var body: some View {
        Form {
            Section(
                header: Text("Server"),
                footer: Text("Configure authentication for this server")
            ) {
                Text(baseUrl)
                    .foregroundColor(.secondary)
            }

            Section(
                header: Text("Authentication")
            ) {
                Picker("Type", selection: $authType) {
                    ForEach(AuthType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            if authType == .basic {
                Section(header: Text("Credentials")) {
                    TextField("Username", text: $username)
                        .disableAutocapitalization()
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)
                }
            } else if authType == .token {
                Section(header: Text("Access Token")) {
                    SecureField("Token", text: $token)
                        .disableAutocapitalization()
                        .disableAutocorrection(true)

                    Text("Enter your ntfy access token")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(action: testConnection) {
                    HStack {
                        Spacer()
                        if testInProgress {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Test Authentication")
                        }
                        Spacer()
                    }
                }
                .disabled(testInProgress)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("Success") ? .green : .red)
                }
            }

            Section {
                Button(action: saveAuth) {
                    HStack {
                        Spacer()
                        Text("Save")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle("Server Auth")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadExistingAuth()
        }
    }
    
    private var isValid: Bool {
        switch authType {
        case .none:
            return true
        case .basic:
            return !username.isEmpty && !password.isEmpty
        case .token:
            return !token.isEmpty
        }
    }
    
    private func loadExistingAuth() {
        guard let user = existingUser ?? store.getUser(baseUrl: baseUrl) else {
            return
        }
        
        // Check if it's token auth
        if let password = user.password, password.hasPrefix("TOKEN:") {
            authType = .token
            token = String(password.dropFirst(6))
        } else {
            authType = .basic
            username = user.username ?? ""
            password = user.password ?? ""
        }
    }
    
    private func saveAuth() {
        switch authType {
        case .none:
            // Remove existing credentials if any
            if let user = store.getUser(baseUrl: baseUrl) {
                store.delete(user: user)
            }
        case .token:
            store.saveUserWithToken(baseUrl: baseUrl, token: token)
        case .basic:
            store.saveUser(baseUrl: baseUrl, username: username, password: password)
        }
        // Save the server URL in preferences so it persists in the server list
        store.saveServer(baseUrl: baseUrl)
        presentationMode.wrappedValue.dismiss()
    }
    
    private func testConnection() {
        testInProgress = true
        testResult = nil
        
        // Build URL with auth
        let urlComponents = URLComponents(string: "\(baseUrl)/_check")
        
        var request = URLRequest(url: urlComponents!.url!)
        request.httpMethod = "GET"
        
        if authType == .token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                testInProgress = false
                if let error = error {
                    testResult = "Error: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        testResult = "✅ Success! Connection working."
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        testResult = "❌ Authentication failed. Check your credentials."
                    } else {
                        testResult = "❌ Server returned status \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
}

/// View for listing and managing servers with authentication
struct ServerListView: View {
    @EnvironmentObject private var store: Store
    @FetchRequest(sortDescriptors: []) var subscriptions: FetchedResults<Subscription>

    @State private var showAddServer = false
    @State private var newServerUrl: String = ""
    @State private var showAuthForNewServer = false
    @State private var pendingServerUrl: String = ""

    /// Get unique server URLs from saved servers + subscriptions
    private var serverUrls: [String] {
        var urls = Set(store.getServers())
        urls.formUnion(subscriptions.compactMap { $0.baseUrl })
        return urls.sorted()
    }

    var body: some View {
        List {
            ForEach(serverUrls, id: \.self) { url in
                NavigationLink(destination: ServerAuthView(baseUrl: url)) {
                    ServerRowView(baseUrl: url)
                }
            }

            Button(action: { showAddServer = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Server")
                }
            }

            NavigationLink(destination: ServerAuthView(baseUrl: pendingServerUrl), isActive: $showAuthForNewServer) {
                EmptyView()
            }
            .hidden()
        }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet(newServerUrl: $newServerUrl, onAdd: addServer)
        }
    }

    private func addServer() {
        var url = newServerUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        // Remove trailing slash
        while url.hasSuffix("/") {
            url.removeLast()
        }
        pendingServerUrl = url
        newServerUrl = ""
        showAddServer = false
        // Navigate to auth config after a brief delay to let sheet dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showAuthForNewServer = true
        }
    }
}

/// Row view for a server
struct ServerRowView: View {
    @EnvironmentObject private var store: Store

    let baseUrl: String

    @State private var serverReachable: Bool? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(shortUrl(url: baseUrl))
                    .font(.body)

                if let user = store.getUser(baseUrl: baseUrl) {
                    if let password = user.password, password.hasPrefix("TOKEN:") {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.caption)
                            Text("Token configured")
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    } else if let username = user.username {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                            Text(username)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                } else {
                    Text("No authentication")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Connection status based on health check
            if let reachable = serverReachable {
                Circle()
                    .fill(reachable ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
            }
        }
        .onAppear {
            checkServerHealth()
        }
    }

    private func checkServerHealth() {
        serverReachable = nil
        guard let url = URL(string: "\(baseUrl)/v1/health") else {
            serverReachable = false
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    serverReachable = true
                } else {
                    serverReachable = false
                }
            }
        }.resume()
    }
}

/// Sheet for adding a new server
struct AddServerSheet: View {
    @Binding var newServerUrl: String
    let onAdd: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(
                    footer: Text("Enter the ntfy server URL")
                ) {
                    TextField("https://ntfy.example.com", text: $newServerUrl)
                        .disableAutocapitalization()
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd()
                        dismiss()
                    }
                    .disabled(newServerUrl.isEmpty)
                }
            }
        }
    }
}
