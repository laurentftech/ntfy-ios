import SwiftUI
import CoreData

/// Authentication type for server
enum AuthType: String, CaseIterable {
    case basic = "Username/Password"
    case token = "Access Token"
}

/// View for configuring server authentication (username/password or token)
struct ServerAuthView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    
    let baseUrl: String
    let existingUser: User?
    
    @State private var authType: AuthType = .basic
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
        NavigationView {
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
                } else {
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
                                Text("Test Connection")
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
            }
            .navigationTitle("Server Auth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAuth()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadExistingAuth()
            }
        }
    }
    
    private var isValid: Bool {
        if authType == .basic {
            return !username.isEmpty && !password.isEmpty
        } else {
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
        if authType == .token {
            store.saveUserWithToken(baseUrl: baseUrl, token: token)
        } else {
            store.saveUser(baseUrl: baseUrl, username: username, password: password)
        }
        dismiss()
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
    
    /// Get unique base URLs from subscriptions
    private var serverUrls: [String] {
        let urls = subscriptions.compactMap { $0.baseUrl }
        return Array(Set(urls)).sorted()
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
        }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet(newServerUrl: $newServerUrl, onAdd: addServer)
        }
    }
    
    private func addServer() {
        showAddServer = false
        // Navigate to auth config for new server
    }
}

/// Row view for a server
struct ServerRowView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appDelegate: AppDelegate

    let baseUrl: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(baseUrl)
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
                    Text("Not configured")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // Add connection status indicator - safely access pollingService via appDelegate
            connectionStatusView
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        // Safely access the connection state with a default value if pollingService is not available
        let state = getConnectionState()

        Circle()
            .fill(connectionColor(for: state))
            .frame(width: 10, height: 10)
            .help(state.rawValue)
    }

    private func getConnectionState() -> ConnectionState {
        // Use appDelegate.pollingService like SubscriptionListView does
        // This prevents crashes when the environment object is not provided
        guard let pollingService = appDelegate.pollingService else {
            return .disconnected
        }
        return pollingService.connectionStates[baseUrl] ?? .disconnected
    }

    private func connectionColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
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
