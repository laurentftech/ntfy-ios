import Foundation

/// PollingService - Manages long-polling connections for ntfy subscriptions
/// Uses NtfyClient from ntfy-macos for reliable, continuous polling
/// This provides an alternative to Firebase push notifications
class PollingService: NSObject {
    
    // MARK: - Properties
    
    private let tag = "PollingService"
    
    /// NtfyClients per server URL (one client can handle multiple topics)
    private var clients: [String: NtfyClient] = [:]
    
    /// Track subscriptions for each client
    private var subscriptionsByServer: [String: [Subscription]] = [:]
    
    /// Delegate for receiving messages
    weak var delegate: PollingServiceDelegate?
    
    /// Whether polling is currently active
    private(set) var isPolling = false
    
    // MARK: - Initialization
    
    override init() {
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
        
        // Start a client for each server
        for (serverUrl, subs) in subscriptionsByServer {
            let topics = subs.compactMap { $0.topic }
            guard !topics.isEmpty else { continue }
            
            // Get auth token for this server (if any)
            let authToken = getAuthToken(for: serverUrl)
            
            let client = NtfyClient(
                serverURL: serverUrl,
                topics: topics,
                authToken: authToken,
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
            if clients[baseUrl] != nil {
                // Client exists but might not have this topic
                // For simplicity, we'll need to restart with new topic
                Log.d(tag, "Adding subscription to existing client: \(baseUrl)/\(topic)")
                // TODO: Handle adding topic dynamically
            } else {
                // Create new client for this server
                let authToken = getAuthToken(for: baseUrl)
                let client = NtfyClient(
                    serverURL: baseUrl,
                    topics: [topic],
                    authToken: authToken,
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
    
    private func getAuthToken(for serverUrl: String) -> String? {
        // TODO: Get token from Store for authenticated servers
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
    }
    
    func ntfyClientDidConnect(_ client: NtfyClient) {
        Log.d(tag, "Connected to server")
    }
    
    func ntfyClientDidDisconnect(_ client: NtfyClient) {
        Log.d(tag, "Disconnected from server")
    }
}

// MARK: - Delegate Protocol

protocol PollingServiceDelegate: AnyObject {
    func pollingService(_ service: PollingService, didReceiveMessage message: Message, for subscription: Subscription)
}
