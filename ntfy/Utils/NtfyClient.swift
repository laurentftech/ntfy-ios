import Foundation

// MARK: - NtfyClient Delegate Protocol

/// Delegate protocol for receiving messages from the NtfyClient
/// This is adapted from ntfy-macos for use in ntfy-ios
@preconcurrency protocol NtfyClientDelegate: AnyObject {
    func ntfyClient(_ client: NtfyClient, didReceiveMessage message: Message)
    func ntfyClient(_ client: NtfyClient, didEncounterError error: Error)
    func ntfyClientDidConnect(_ client: NtfyClient)
    func ntfyClientDidDisconnect(_ client: NtfyClient)
    func ntfyClientWillConnect(_ client: NtfyClient)
}

// MARK: - NtfyClient

/// Long-polling client for ntfy topics
/// This is adapted from ntfy-macos: https://github.com/laurentftech/ntfy-macos
/// Provides continuous polling with automatic reconnection
final class NtfyClient: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let serverURL: String
    private let topics: [String]
    private let fetchMissed: Bool
    private let lock = NSLock()
    private var _authToken: String?
    
    private var authToken: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _authToken
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _authToken = newValue
        }
    }
    
    weak var delegate: NtfyClientDelegate?
    
    private var session: URLSession!
    private let delegateQueue: OperationQueue
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 2.0
    private let maxReconnectDelay: TimeInterval = 300.0  // 5 minutes max
    private var reconnectTimer: Timer?
    private var isConnecting = false
    private var shouldReconnect = true
    private var retryAfterDelay: TimeInterval?  // From Retry-After header
    private var lastMessageTime: Int64  // Track last message timestamp for fetch_missed
    private let lastMessageTimeKey: String  // UserDefaults key for persistence
    
    private let tag = "NtfyClient"
    
    // MARK: - Initialization
    
    init(serverURL: String, topics: [String], authToken: String? = nil, fetchMissed: Bool = false) {
        self.serverURL = serverURL
        self.topics = topics
        self._authToken = authToken
        self.fetchMissed = fetchMissed
        
        // Restore last message time from UserDefaults for fetch_missed
        let topicsKey = topics.sorted().joined(separator: ",")
        self.lastMessageTimeKey = "lastMessageTime-\(serverURL)-\(topicsKey)"
        self.lastMessageTime = Int64(UserDefaults.standard.integer(forKey: lastMessageTimeKey))
        
        // Create a dedicated serial queue for URLSession callbacks
        self.delegateQueue = OperationQueue()
        self.delegateQueue.maxConcurrentOperationCount = 1
        self.delegateQueue.name = "com.ntfy-ios.urlsession"
        
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        config.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Public API
    
    /// Start connecting to the ntfy server
    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        
        let topicsString = topics.joined(separator: ",")
        guard var components = URLComponents(string: serverURL) else {
            isConnecting = false
            return
        }
        
        components.path = "/\(topicsString)/json"
        
        // Add since parameter to fetch missed messages when enabled
        if fetchMissed {
            if lastMessageTime > 0 {
                // Reconnect: only fetch messages since the last one we received
                components.queryItems = [URLQueryItem(name: "since", value: String(lastMessageTime))]
            } else {
                // First connect: fetch all cached messages
                components.queryItems = [URLQueryItem(name: "since", value: "all")]
            }
        }
        
        guard let url = components.url else {
            isConnecting = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        buffer.removeAll()
        dataTask = session.dataTask(with: request)
        dataTask?.resume()
        
        Log.d(tag, "Connecting to ntfy: \(url.absoluteString)")
    }
    
    /// Disconnect from the ntfy server
    func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        dataTask?.cancel()
        dataTask = nil
        isConnecting = false
        buffer.removeAll()
    }
    
    /// Update the auth token and reconnect if connected
    func updateAuthToken(_ token: String?) {
        self.authToken = token
        if dataTask != nil {
            reconnect()
        }
    }
    
    // MARK: - Private Methods
    
    /// Thread-safe delegate call helper
    private func callDelegate(_ block: @escaping @Sendable (NtfyClientDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let delegate = self.delegate else { return }
            block(delegate)
        }
    }
    
    /// Reconnect to the server with exponential backoff
    private func reconnect() {
        guard shouldReconnect else { return }
        
        dataTask?.cancel()
        dataTask = nil
        isConnecting = false
        
        // Calculate delay with exponential backoff
        var delay: TimeInterval
        
        if let retryAfter = retryAfterDelay {
            // Server told us exactly when to retry (Retry-After header)
            delay = retryAfter
            retryAfterDelay = nil  // Clear for next time
            Log.d(tag, "Server requested retry after \(Int(delay)) seconds")
        } else {
            // Exponential backoff: 2s, 4s, 8s, 16s, 32s, 64s, 128s, 256s, 300s (capped)
            delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        }
        
        // Add jitter (±10%) to prevent thundering herd
        let jitter = delay * Double.random(in: -0.1...0.1)
        delay += jitter
        
        reconnectAttempts += 1
        
        if reconnectAttempts <= maxReconnectAttempts {
            Log.d(tag, "Reconnecting in \(String(format: "%.1f", delay)) seconds (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")
            
            // Schedule timer on main thread to ensure RunLoop is active
            DispatchQueue.main.async { [weak self] in
                self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.connect()
                }
            }
        } else {
            Log.e(tag, "Max reconnection attempts reached. Please restart the service.")
            let error = NSError(
                domain: "NtfyClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Max reconnection attempts reached"]
            )
            callDelegate { delegate in
                delegate.ntfyClient(self, didEncounterError: error)
            }
        }
    }
    
    /// Parse Retry-After header value (can be seconds or HTTP date)
    func parseRetryAfter(_ value: String) -> TimeInterval {
        // Try parsing as seconds first
        if let seconds = TimeInterval(value) {
            return max(seconds, 1.0)  // At least 1 second
        }
        
        // Try parsing as HTTP date (e.g., "Sun, 18 Jan 2026 23:59:59 GMT")
        let httpDateFormatter = DateFormatter()
        httpDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        httpDateFormatter.timeZone = TimeZone(identifier: "GMT")
        
        // RFC 7231 formats
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",  // IMF-fixdate
            "EEEE, dd-MMM-yy HH:mm:ss zzz",   // RFC 850
            "EEE MMM d HH:mm:ss yyyy"          // ANSI C asctime()
        ]
        
        for format in formats {
            httpDateFormatter.dateFormat = format
            if let date = httpDateFormatter.date(from: value) {
                let delay = date.timeIntervalSinceNow
                return max(delay, 1.0)  // At least 1 second, even if date is in past
            }
        }
        
        // Fallback if parsing fails
        return 30.0
    }
    
    /// Process a single NDJSON line
    private func processLine(_ line: String) {
        guard !line.isEmpty else { return }
        
        do {
            let data = Data(line.utf8)
            var message = try JSONDecoder().decode(Message.self, from: data)
            
            // Workaround: Some ntfy servers don't return actions as a JSON array,
            // instead they URL-encode them and append to the message field.
            // Parse actions from message if actions field is nil.
            if message.actions == nil, let msg = message.message, msg.contains("&actions=") {
                if let actionsRange = msg.range(of: "&actions=") {
                    let encodedActions = String(msg[actionsRange.upperBound...])
                    // Clean up message by removing the actions part
                    let cleanMessage = String(msg[..<actionsRange.lowerBound])
                    if let decodedActions = encodedActions.removingPercentEncoding {
                        if let actionsData = decodedActions.data(using: .utf8),
                           let parsedActions = try? JSONDecoder().decode([Action].self, from: actionsData) {
                            // Create new message with actions and cleaned message
                            message.actions = parsedActions
                            message.message = cleanMessage
                        }
                    }
                }
            }
            
            // Track latest message time for fetch_missed reconnects
            if message.time > lastMessageTime {
                lastMessageTime = message.time
                if fetchMissed {
                    UserDefaults.standard.set(lastMessageTime, forKey: lastMessageTimeKey)
                }
            }
            
            if message.event == "message" {
                callDelegate { delegate in
                    delegate.ntfyClient(self, didReceiveMessage: message)
                }
            }
        } catch {
            Log.e(tag, "Failed to decode message: \(error)")
        }
    }
}

// MARK: - URLSessionDataDelegate

extension NtfyClient: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        
        while let newlineRange = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)
            
            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                processLine(line)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        isConnecting = false
        
        if let error = error {
            // Don't log cancelled errors (normal during reconnect)
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                Log.e(tag, "Connection error: \(error.localizedDescription)")
            }
            callDelegate { delegate in
                delegate.ntfyClient(self, didEncounterError: error)
                delegate.ntfyClientDidDisconnect(self)
            }
            reconnect()
        } else {
            Log.d(tag, "Connection closed by server")
            callDelegate { delegate in
                delegate.ntfyClientDidDisconnect(self)
            }
            if shouldReconnect {
                reconnect()
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        
        if httpResponse.statusCode == 200 {
            isConnecting = false
            reconnectAttempts = 0
            callDelegate { delegate in
                delegate.ntfyClientDidConnect(self)
            }
            completionHandler(.allow)
        } else {
            Log.e(tag, "Server returned status code: \(httpResponse.statusCode)")
            
            // Handle rate limiting (429) - extract Retry-After header
            if httpResponse.statusCode == 429 {
                if let retryAfterString = httpResponse.value(forHTTPHeaderField: "Retry-After") {
                    retryAfterDelay = parseRetryAfter(retryAfterString)
                } else {
                    // No Retry-After header, use a conservative default for 429
                    retryAfterDelay = 30.0
                }
            }
            
            completionHandler(.cancel)
        }
    }
}
