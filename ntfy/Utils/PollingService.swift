import Foundation
import SwiftUI

/// Connection state for a polling client
enum ConnectionState: String {
    case connected = "Connected"
    case connecting = "Connecting..."
    case disconnected = "Disconnected"
}

/// PollingService - Manages long-polling connections for ntfy subscriptions
/// Uses NtfyClient from ntfy-macos for reliable, continuous polling
/// This provides an alternative to Firebase push notifications
class PollingService: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let tag = "PollingService"
    
    /// NtfyClients per server URL (one client can handle multiple topics)
    private var clients: [String: NtfyClient] = [:]
    
    /// Track subscriptions for each client
    private var subscriptionsByServer: [String: [Subscription]] = [:]
    
    /// Track connection states per server URL
    @Published public var connectionStates: [String: ConnectionState] = [:]
    
    /// Delegate for receiving messages
    weak var delegate: PollingServiceDelegate?
    
    /// Whether polling is currently active
    private(set) var isPolling = false
    
    /// Reference to the Store for getting user credentials
    private var store: Store?
    
    // MARK: - Public API
    
    /// Get connection state for a specific server
    func connectionState(for serverUrl: String) -> ConnectionState {
        return connectionStates[serverUrl] ?? .disconnected
    }
    
    /// Observe connection states (for SwiftUI)
    var connectionStatesPublisher: Published<[String: ConnectionState]>.Publisher {
        return $connectionStates
    }
    
    // MARK: - Initialization
    
    init(store: Store? = nil) {
        self.store = store
        super.init()
    }
    
    // MARK: - Public API
    
    /// Start polling for all subscriptions
    func startPolling(subscriptions: [Subscription]) {
        Log.d(tag, "Starting polling for \(subscriptions.count) subscriptions")
        
        // Group subscriptions by server
        var subscriptionsByServer: [String: [Subscription]] = [:]
        for subscription in subscriptions {
            guard let baseUrl = subscription.baseUrl else { continue }
            if subscriptionsByServer[baseUrl] == nil {
                subscriptionsByServer[baseUrl] = []
            }
            subscriptionsByServer[baseUrl]?.append(subscription)
        }
        
        self.subscriptionsByServer = subscriptionsByServer
        self.isPolling = true
        
        // Initialize connection states to connecting
        for serverUrl in subscriptionsByServer.keys {
            connectionStates[serverUrl] = .connecting
        }
        
        // Start a client for each server
        for (serverUrl, subs) in subscriptionsByServer {
            let topics = subs.compactMap { $0.topic }
            guard !topics.isEmpty else { continue }
            
            // Get auth header and bearer token for this server (if any)
            let authHeader = getAuthHeader(for: serverUrl)
            let bearerToken = getBearerToken(for: serverUrl)
            
            let client = NtfyClient(
                serverURL: serverUrl,
                topics: topics,
                authHeader: authHeader,
                bearerToken: bearerToken,
                fetchMissed: true
            )
            client.delegate = self
            clients[serverUrl] = client
            client.connect()
        }
    }
    
    /// Stop all polling
    func stopPolling() {
        Log.d(tag, "Stopping all polling")
        
        isPolling = false
        
        for (_, client) in clients {
            client.disconnect()
        }
        clients.removeAll()
        subscriptionsByServer.removeAll()
    }
    
    /// Add a new subscription to poll
    func addSubscription(_ subscription: Subscription) {
        guard let baseUrl = subscription.baseUrl, let topic = subscription.topic else {
            return
        }
        
        if isPolling {
            if let existingClient = clients[baseUrl] {
                // Client exists but might not have this topic
                // For simplicity, we'll need to restart with new topic
                Log.d(tag, "Adding subscription to existing client: \(baseUrl)/\(topic)")
                // TODO: Handle adding topic dynamically
            } else {
                // Create new client for this server
                let authHeader = getAuthHeader(for: baseUrl)
                let bearerToken = getBearerToken(for: baseUrl)
                let client = NtfyClient(
                    serverURL: baseUrl,
                    topics: [topic],
                    authHeader: authHeader,
                    bearerToken: bearerToken,
                    fetchMissed: true
                )
                client.delegate = self
                clients[baseUrl] = client
                client.connect()
            }
        }
    }
    
    /// Remove a subscription from polling
    func removeSubscription(_ subscription: Subscription) {
        guard let baseUrl = subscription.baseUrl else { return }
        
        if let client = clients[baseUrl] {
            // For now, we disconnect the whole client
            // A more sophisticated approach would track per-topic subscriptions
            client.disconnect()
            clients.removeValue(forKey: baseUrl)
        }
    }
    
    // MARK: - Private Methods
    
    /// Get authorization header for a server URL (supports both Basic Auth and Bearer Token)
    private func getAuthHeader(for serverUrl: String) -> String? {
        guard let store = store else {
            return nil
        }
        
        let authType = store.getAuthType(for: serverUrl)
        
        if authType == .token {
            // Bearer token authentication
            if let token = store.getToken(for: serverUrl) {
                return "Bearer \(token)"
            }
        }
        
        // Basic authentication
        guard let user = store.getUser(baseUrl: serverUrl) else {
            return nil
        }
        // Create Basic Auth header: "Basic base64(username:password)"
        let basicUser = user.toBasicUser()
        return "Basic " + String(format: "%@:%@", basicUser.username, basicUser.password)
            .data(using: String.Encoding.utf8)!
            .base64EncodedString()
    }
    
    /// Get Bearer token for a server URL (if configured)
    private func getBearerToken(for serverUrl: String) -> String? {
        // TODO: Get token from Store when token-based auth is implemented
        return nil
    }
    
    /// Find the subscription that matches a message
    private func findSubscription(for topic: String) -> Subscription? {
        for (_, subs) in subscriptionsByServer {
            if let sub = subs.first(where: { $0.topic == topic }) {
                return sub
            }
        }
        return nil
    }
}

// MARK: - NtfyClientDelegate

extension PollingService: NtfyClientDelegate {
    
    func ntfyClient(_ client: NtfyClient, didReceiveMessage message: Message) {
        // Find the matching subscription
        guard let subscription = findSubscription(for: message.topic) else {
            Log.w(tag, "Received message for unknown topic: \(message.topic)")
            return
        }
        
        // Notify delegate
        delegate?.pollingService(self, didReceiveMessage: message, for: subscription)
    }
    
    func ntfyClient(_ client: NtfyClient, didEncounterError error: Error) {
        Log.e(tag, "Polling error: \(error.localizedDescription)")
        // Update connection state to disconnected on error
        if let serverUrl = clients.first(where: { $0.value === client })?.key {
            connectionStates[serverUrl] = .disconnected
        }
    }
    
    func ntfyClientDidConnect(_ client: NtfyClient) {
        Log.d(tag, "Connected to server")
        // Update connection state
        if let serverUrl = clients.first(where: { $0.value === client })?.key {
            connectionStates[serverUrl] = .connected
        }
    }
    
    func ntfyClientDidDisconnect(_ client: NtfyClient) {
        Log.d(tag, "Disconnected from server")
        // Update connection state
        if let serverUrl = clients.first(where: { $0.value === client })?.key {
            connectionStates[serverUrl] = .disconnected
        }
    }
    
    func ntfyClientWillConnect(_ client: NtfyClient) {
        // Optional: Not used in current implementation
    }
}

// MARK: - Delegate Protocol

protocol PollingServiceDelegate: AnyObject {
    func pollingService(_ service: PollingService, didReceiveMessage message: Message, for subscription: Subscription)
}
