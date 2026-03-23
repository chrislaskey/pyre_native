import Foundation
import Combine
import SwiftPhoenixClient

/// Phoenix Socket wrapper using SwiftPhoenixClient library
/// Now ObservableObject so ViewModels can reactively observe connection state changes
///
/// Implements circuit breaker pattern to prevent reconnection storms when backend crashes.
/// SwiftPhoenixClient auto-reconnects immediately, so we detect crash loops and add backoff.
class PhoenixSocket: ObservableObject {
    /// Connection state - updates in real-time as socket connects/disconnects
    /// ViewModels can subscribe to changes using Combine:
    ///
    ///     socket?.$isConnected
    ///         .sink { connected in
    ///             self.isConnected = connected
    ///         }
    ///         .store(in: &cancellables)
    @Published var isConnected = false
    
    let url: String
    private var socket: Socket
    private var socketErrorCallback: ((Error) -> Void)?
    
    // Circuit breaker for reconnection storm detection
    private var connectionAttempts: [(timestamp: Date, success: Bool)] = []
    private let maxFailuresInWindow = 3  // Max failures before circuit breaks
    private let failureWindow: TimeInterval = 5.0  // 5 second window
    private var isCircuitOpen = false
    private var reconnectTask: Task<Void, Never>?
    private let backoff = PhoenixSocketReconnectionHelpers()
    
    // Stability tracking - don't reset backoff until connection is stable
    private var connectionStabilityTask: Task<Void, Never>?
    private let stabilityWindow: TimeInterval = 5.0  // Must stay connected for 5s
    
    // Track intentional disconnects to avoid triggering reconnection logic
    private var isIntentionallyDisconnecting = false
    
    init(url: String, params: [String: Any] = [:]) {
        self.url = url
        self.socket = Socket(url, params: params)
        
        // Setup socket callbacks
        socket.onOpen { [weak self] in
            guard let self = self else { return }
            DebugLogger.info("✅ Socket opened")
            
            Task { @MainActor in
                self.isConnected = true
                self.isCircuitOpen = false  // Allow connection to proceed
                
                // Start stability timer - only reset backoff if connection stays up
                await self.startStabilityTimer()
            }
        }
        
        socket.onClose { [weak self] in
            guard let self = self else { return }
            DebugLogger.info("👋 Socket closed")
            
            Task { @MainActor in
                self.isConnected = false
                
                // Skip reconnection logic if this was an intentional disconnect
                guard !self.isIntentionallyDisconnecting else {
                    DebugLogger.debug("👋 Intentional disconnect - skipping reconnection logic")
                    self.isIntentionallyDisconnecting = false
                    return
                }
                
                // Record failure and check circuit breaker
                self.recordConnectionFailure()
                await self.checkCircuitBreaker()
            }
        }
        
        socket.onError { [weak self] error, response in
            guard let self = self else { return }

            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let nsError = error as NSError
            let unifiedError = NSError(
                domain: nsError.domain,
                code: nsError.code,
                userInfo: nsError.userInfo.merging([
                    "NSLocalizedDescriptionKey": "Socket connection failed",
                    "source": "PhoenixSocket",
                    "statusCode": statusCode as Any,
                    "url": response?.url?.absoluteString as Any
                ]) { current, _ in current }
            )

            DebugLogger.debug("❌ Socket error: \(unifiedError)")
            
            Task { @MainActor in
                self.socketErrorCallback?(unifiedError)
                self.recordConnectionFailure()
            }
        }
    }
    
    /// Register a callback for socket errors
    ///
    /// - Parameter callback: Handler called with error
    /// - Returns: Self for chaining
    func onSocketError(_ callback: @escaping (Error) -> Void) {
        self.socketErrorCallback = callback
    }
    
    /// Start timer to check connection stability before resetting backoff
    @MainActor
    private func startStabilityTimer() async {
        // Cancel any existing stability timer
        connectionStabilityTask?.cancel()
        
        DebugLogger.debug("⏱️ Starting stability timer (\(stabilityWindow)s)")
        
        connectionStabilityTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(stabilityWindow * 1_000_000_000))
            
            guard !Task.isCancelled else {
                DebugLogger.warning("⚠️ Stability timer cancelled (connection failed)")
                return
            }
            
            // Connection has been stable for the required time
            self.markConnectionStable()
        }
    }
    
    /// Mark connection as stable and reset circuit breaker/backoff
    @MainActor
    private func markConnectionStable() {
        guard isConnected else {
            DebugLogger.warning("⚠️ Connection not stable (already disconnected)")
            return
        }
        
        DebugLogger.info("✅ Connection STABLE for \(stabilityWindow)s - resetting circuit & backoff")
        
        // Clear failure history
        connectionAttempts.removeAll()
        
        // Reset backoff for next failure
        backoff.reset()
        
        // Circuit is definitely closed
        isCircuitOpen = false
    }
    
    /// Record a connection failure for circuit breaker
    @MainActor
    private func recordConnectionFailure() {
        // Cancel stability timer - connection failed before becoming stable
        connectionStabilityTask?.cancel()
        
        let now = Date()
        connectionAttempts.append((timestamp: now, success: false))
        
        // Clean old attempts outside the window
        connectionAttempts.removeAll { now.timeIntervalSince($0.timestamp) > failureWindow }
    }
    
    /// Check if we're in a reconnection storm and open circuit breaker
    @MainActor
    private func checkCircuitBreaker() async {
        // Count recent failures
        let recentFailures = connectionAttempts.filter { !$0.success }.count
        
        if recentFailures >= maxFailuresInWindow && !isCircuitOpen {
            // Open circuit breaker - stop the reconnection storm
            isCircuitOpen = true
            DebugLogger.warning("🚨 Circuit breaker OPEN - detected reconnection storm (\(recentFailures) failures)")
            
            // Disconnect to stop auto-reconnect
            socket.disconnect()
            
            // Schedule reconnection with backoff
            await scheduleReconnectWithBackoff()
        }
    }
    
    /// Schedule a reconnection attempt with exponential backoff
    @MainActor
    private func scheduleReconnectWithBackoff() async {
        // Don't schedule reconnects in offline mode
        guard !PhoenixChannelService.shared.isOfflineMode else {
            DebugLogger.debug("📴 Skipping reconnect scheduling - offline mode active")
            return
        }
        
        // Cancel any existing reconnect task
        reconnectTask?.cancel()
        
        let delay = backoff.nextDelay()
        DebugLogger.info("⏰ Scheduling reconnect in \(String(format: "%.1f", delay))s")
        
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else {
                DebugLogger.warning("⚠️ Reconnect task cancelled")
                return
            }
            
            await self.attemptReconnect()
        }
    }
    
    /// Attempt to reconnect after backoff delay
    @MainActor
    private func attemptReconnect() async {
        // Don't attempt reconnects in offline mode
        guard !PhoenixChannelService.shared.isOfflineMode else {
            DebugLogger.debug("📴 Skipping reconnect attempt - offline mode active")
            return
        }
        
        DebugLogger.info("🔄 Attempting reconnect after backoff")
        
        // Allow this reconnection attempt
        isCircuitOpen = false
        
        // Reconnect - onOpen/onClose handlers will track success/failure
        socket.connect()
        
        // Note: We no longer wait here. The stability timer in onOpen
        // will determine if the connection is actually stable.
        // If it fails quickly, onClose will trigger circuit breaker check.
    }
    
    func connect() {
        DebugLogger.logConnection(url: url)
        socket.connect()
    }
    
    func disconnect() {
        DebugLogger.logDisconnection(url: url)
        
        // Mark as intentional disconnect to prevent onClose from triggering reconnection
        isIntentionallyDisconnecting = true
        
        // Cancel any pending reconnect tasks to prevent zombie reconnections
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // Cancel stability timer
        connectionStabilityTask?.cancel()
        connectionStabilityTask = nil
        
        // Clear socket error callback to prevent stale closures
        socketErrorCallback = nil
        
        // Clear failure history so we don't carry over old failures
        connectionAttempts.removeAll()
        
        socket.disconnect()
    }
    
    func channel(_ topic: String, params: [String: Any] = [:]) -> PhoenixChannel {
        // Don't cache channels - SwiftPhoenixClient requires each channel instance
        // to only be joined once. Create a fresh channel each time.
        DebugLogger.debug("🆕 Creating new channel: \(topic) with params: \(params)")
        let channel = PhoenixChannel(topic: topic, params: params, socket: socket)
        return channel
    }
    
    func removeChannel(_ channel: PhoenixChannel) {
        channel.leave()
        socket.remove(channel.underlyingChannel)
        DebugLogger.debug("🗑️ Removed channel: \(channel.topic)")
    }

    // MARK: - Static Helpers

    /// Build WebSocket URL from base URL and channel path.
    ///
    /// - Parameters:
    ///   - baseURL: The organization's base URL (e.g., "http://localhost:4000/pyre")
    ///   - channelPath: The channel path (e.g., "/users/log-in")
    /// - Returns: Full WebSocket URL (e.g., "ws://localhost:4000/pyre/websocket")
    static func buildWebSocketURL(connection: Connection, channelPath: String) -> String {
        let baseUrl = connection.baseUrl

        // Determine websocket protocol based on HTTP schema
        let wsProtocol: String
        if baseUrl.hasPrefix("https://") {
            wsProtocol = "wss://"
        } else if baseUrl.hasPrefix("http://") {
            wsProtocol = "ws://"
        } else {
            // No schema - assume https (and thus wss)
            wsProtocol = "wss://"
        }
        
        // Strip http/https schema from baseUrl
        let cleanedURL = baseUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        
        return "\(wsProtocol)\(cleanedURL)/websocket"
    }
}

// MARK: - Phoenix Channel Wrapper

class PhoenixChannel {
    let topic: String
    private var channel: Channel
    
    /// Access to underlying Channel for removal
    var underlyingChannel: Channel {
        return channel
    }
    
    init(topic: String, params: [String: Any] = [:], socket: Socket) {
        self.topic = topic
        self.channel = socket.channel(topic, params: params)
    }
    
    func join(callback: ((Result<[String: Any], Error>) -> Void)? = nil) {
        DebugLogger.logChannelJoined(topic: topic)
        
        channel.join()
            .receive("ok") { message in
                DebugLogger.logReceive(topic: self.topic, event: "phx_reply", payload: message.payload)
                callback?(.success(message.payload))
            }
            .receive("error") { message in
                DebugLogger.error("❌ Join failed: \(self.topic)")

                let error = NSError(
                    domain: "PhoenixChannel",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Join failed",
                        "message": message.payload["response"] as Any
                    ]
                )

                callback?(.failure(error))
            }
    }
    
    func leave() {
        DebugLogger.debug("👋 Leaving channel: \(topic)")
        channel.leave()
    }
    
    func on(_ event: String, callback: @escaping ([String: Any]) -> Void) {
        channel.on(event) { message in
            DebugLogger.logReceive(topic: self.topic, event: event, payload: message.payload)
            callback(message.payload)
        }
    }
    
    func push(_ event: String, _ payload: [String: Any], callback: ((Result<[String: Any], Error>) -> Void)? = nil) {
        DebugLogger.logPush(topic: topic, event: event, payload: payload)
        
        channel.push(event, payload: payload)
            .receive("ok") { message in
                DebugLogger.info("✅ Push successful: \(event)")
                DebugLogger.logReceive(topic: self.topic, event: "\(event)_reply", payload: message.payload)
                callback?(.success(message.payload))
            }
            .receive("error") { message in
                DebugLogger.error("❌ Push failed: \(event)")

                let error = NSError(
                    domain: "PhoenixChannel",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Push failed",
                        "message": message.payload["response"] as Any
                    ]
                )

                callback?(.failure(error))
            }
    }
}

/// Manages exponential backoff with jitter for socket reconnection attempts.
/// Prevents thundering herd problems when backend crashes.
///
/// Usage:
/// ```swift
/// let backoff = ReconnectionBackoff()
///
/// func attemptReconnect() {
///     let delay = backoff.nextDelay()
///     Task {
///         try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
///         connect() // Perform actual reconnection
///     }
/// }
///
/// // Reset after successful connection
/// backoff.reset()
/// ```
@MainActor
class PhoenixSocketReconnectionHelpers {
    private var attemptCount: Int = 0
    private let baseDelay: TimeInterval = 1.0      // 1 second
    private let maxDelay: TimeInterval = 30.0      // 30 seconds
    private let jitterFactor: Double = 0.2          // ±20%
    
    /// Get the delay for the next reconnection attempt.
    /// Returns delay in seconds with exponential backoff and jitter.
    func nextDelay() -> TimeInterval {
        attemptCount += 1
        
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s...
        let exponentialDelay = baseDelay * pow(2.0, Double(attemptCount - 1))
        let cappedDelay = min(exponentialDelay, maxDelay)
        
        // Add jitter: ±20% randomness to prevent thundering herd
        let jitterRange = cappedDelay * jitterFactor
        let jitter = Double.random(in: -jitterRange...jitterRange)
        
        let finalDelay = cappedDelay + jitter
        
        DebugLogger.debug(
            "🔄 Reconnect attempt #\(attemptCount) - waiting \(String(format: "%.1f", finalDelay))s"
        )
        
        return finalDelay
    }
    
    /// Reset the backoff counter (call after successful connection)
    func reset() {
        if attemptCount > 0 {
            DebugLogger.debug(
                "✅ Backoff reset after \(attemptCount) attempts"
            )
        }
        attemptCount = 0
    }
    
    /// Get current attempt count (for debugging)
    var currentAttempt: Int {
        attemptCount
    }
}
