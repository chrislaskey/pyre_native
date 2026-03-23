import Foundation
import Combine

/// A managed Phoenix channel connection with automatic lifecycle handling.
///
/// ## Overview
/// `PhoenixChannelLiveView` wraps a Phoenix channel connection, providing:
/// - Automatic socket acquisition/release via ChannelService
/// - Reactive connection state via `@Published` properties
/// - Clean async/await API for pushing events
/// - Automatic cleanup on deinit (no manual release needed)
///
/// ## Usage
/// ```swift
/// class MyViewModel: ObservableObject {
///     @Published var isConnected = false
///     private var channel: PhoenixChannelLiveView?
///
///     func mount() {
///         channel = ChannelService.shared.connect(
///             to: "/users/log-in",
///             connection: myConnection
///         )
///
///         channel?.$isConnected
///             .assign(to: &$isConnected)
///
///         channel?.onJoin { payload in
///             // Handle join response
///         }
///     }
///
///     // No cleanup needed! PhoenixChannelLiveView handles it in deinit.
/// }
/// ```
///
/// ## Thread Safety
/// PhoenixChannelLiveView is `@MainActor` - all state changes happen on main thread.
@MainActor
final class PhoenixChannelLiveView: ObservableObject {
    
    // MARK: - Published State
    
    /// Whether the underlying socket is connected
    @Published private(set) var isConnected = false
    
    /// Whether the channel has successfully joined
    @Published private(set) var isJoined = false
    
    /// Whether a join is currently in progress
    @Published private(set) var isJoining = false
    
    // MARK: - Properties
    
    /// The channel path (e.g., "/users/log-in")
    let path: String
    
    /// The connection this channel belongs to
    let connection: Connection
    
    // MARK: - Private
    
    private let socket: PhoenixSocket
    private var channel: PhoenixChannel?
    private var cancellables = Set<AnyCancellable>()
    private let onRelease: () -> Void
    
    private let joinParams: [String: Any]
    private var joinCallback: (([String: Any]) -> Void)?
    private var joinErrorCallback: ((Error) -> Void)?
    private var eventHandlers: [String: ([String: Any]) -> Void] = [:]
    
    private var socketErrorCallback: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    /// Creates a new PhoenixChannelLiveView. Use `ChannelService.connect()` instead of calling directly.
    init(
        path: String,
        connection: Connection,
        socket: PhoenixSocket,
        joinParams: [String: Any],
        onRelease: @escaping () -> Void
    ) {
        self.path = path
        self.connection = connection
        self.socket = socket
        self.joinParams = joinParams
        self.onRelease = onRelease

        setupBindings()
        joinChannel()
    }
    
    deinit {
        // Capture values needed for cleanup (can't reference self in async context)
        let channelToRemove = channel
        let socketRef = socket
        let releaseCallback = onRelease
        let channelPath = path
        
        // Schedule cleanup on MainActor (deinit is not actor-isolated)
        Task { @MainActor in
            DebugLogger.debug("📺 PhoenixChannelLiveView cleanup: \(channelPath)")
            
            // Leave channel
            if let channel = channelToRemove {
                socketRef.removeChannel(channel)
            }
            
            // Release socket back to pool
            releaseCallback()
        }
    }
    
    // MARK: - Event Handlers
    
    /// Register a callback for successful channel join.
    /// The callback receives the join response payload.
    ///
    /// - Parameter callback: Handler called with join response payload
    /// - Returns: Self for chaining
    @discardableResult
    func onJoin(_ callback: @escaping ([String: Any]) -> Void) -> Self {
        self.joinCallback = callback
        return self
    }
    
    /// Register a callback for socket errors.
    ///
    /// - Parameter callback: Handler called with error
    /// - Returns: Self for chaining
    @discardableResult
    func onSocketError(_ callback: @escaping (Error) -> Void) -> Self {
        self.socketErrorCallback = callback
        return self
    }

    /// Register a callback for channel join errors.
    ///
    /// - Parameter callback: Handler called with error
    /// - Returns: Self for chaining
    @discardableResult
    func onJoinError(_ callback: @escaping (Error) -> Void) -> Self {
        self.joinErrorCallback = callback
        return self
    }
    
    /// Register a handler for a specific event type.
    ///
    /// - Parameters:
    ///   - event: Event name to listen for
    ///   - callback: Handler called with event payload
    /// - Returns: Self for chaining
    @discardableResult
    func on(_ event: String, _ callback: @escaping ([String: Any]) -> Void) -> Self {
        eventHandlers[event] = callback
        channel?.on(event, callback: callback)
        return self
    }
    
    // MARK: - Push Events
    
    /// Push an event to the channel and wait for response.
    ///
    /// - Parameters:
    ///   - event: Event name
    ///   - payload: Event payload
    ///   - timeout: Timeout in seconds (default 5)
    /// - Returns: Response payload
    /// - Throws: Error if push fails or times out
    func push(
        _ event: String,
        _ payload: [String: Any] = [:],
        timeout: TimeInterval = 5
    ) async throws -> [String: Any] {
        // Validate state
        guard isConnected else {
            throw PhoenixChannelLiveViewError.socketDisconnected
        }
        
        guard let channel = channel else {
            throw PhoenixChannelLiveViewError.noChannel
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var didComplete = false
            
            // Setup timeout
            let timeoutTask = DispatchWorkItem { [weak self] in
                guard !didComplete else { return }
                didComplete = true
                DebugLogger.warning("⏰ Push timeout: \(event)")
                continuation.resume(throwing: PhoenixChannelLiveViewError.timeout)
                
                // Mark as disconnected since we timed out
                Task { @MainActor in
                    self?.isConnected = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
            
            // Push event
            channel.push(event, payload) { result in
                guard !didComplete else { return }
                didComplete = true
                timeoutTask.cancel()
                
                switch result {
                case .success(let response):
                    // NOTE: if there is a standard `response` payload, it may make sense to parse and save any information here
                    continuation.resume(returning: response)
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Push an event without waiting for response (fire-and-forget).
    ///
    /// - Parameters:
    ///   - event: Event name
    ///   - payload: Event payload
    func pushAsync(_ event: String, _ payload: [String: Any] = [:]) {
        guard isConnected, let channel = channel else {
            DebugLogger.warning("⚠️ Cannot push \(event): not connected")
            return
        }
        
        channel.push(event, payload, callback: nil)
    }
    
    // MARK: - Reconnection
    
    /// Force reconnect to the channel.
    /// Leaves current channel and rejoins.
    func reconnect() {
        DebugLogger.debug("🔄 Reconnecting channel: \(path)")
        
        // Leave current channel if exists
        if let channel = channel {
            socket.removeChannel(channel)
        }
        
        isJoined = false
        isJoining = false
        channel = nil
        
        // Rejoin
        joinChannel()
    }
    
    // MARK: - Private
    
    private func setupBindings() {
        // Track socket connection state
        socket.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
                
                // If socket disconnected while we thought we were joined, update state
                if !connected {
                    self?.isJoined = false
                }
            }
            .store(in: &cancellables)

        // Forward socket errors
        socket.onSocketError { [weak self] error in
            self?.socketErrorCallback?(error)
        }
    }
    
    private func joinChannel() {
        guard !isJoining else {
            DebugLogger.warning("⚠️ Already joining channel: \(path)")
            return
        }
        
        isJoining = true
        
        // Create channel
        channel = socket.channel(path, params: joinParams)
        
        // Register any pre-configured event handlers
        for (event, handler) in eventHandlers {
            channel?.on(event, callback: handler)
        }
        
        // Join
        channel?.join { [weak self] result in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.isJoining = false
                
                switch result {
                case .success(let payload):
                    DebugLogger.info("✅ Joined channel: \(self.path)")
                    self.isJoined = true
                    
                    // NOTE: if there is a standard `response` payload, it may make sense to parse and save any information here
                    
                    // Call user's join callback
                    self.joinCallback?(payload)
                    
                case .failure(let error):
                    DebugLogger.error("❌ Failed to join channel: \(self.path) - \(error)")
                    
                    let nsError = error as NSError
                    let unifiedError = NSError(
                        domain: nsError.domain,
                        code: nsError.code,
                        userInfo: nsError.userInfo.merging([
                            "NSLocalizedDescriptionKey": "Join failed",
                            "source": "PhoenixChannelLiveView",
                            "channelPath": self.path,
                            "error": error,
                        ]) { current, _ in current }
                    )

                    self.isJoined = false
                    self.joinErrorCallback?(unifiedError)
                }
            }
        }
    }
}

// MARK: - Push Event Helpers

extension PhoenixChannelLiveView {
    /// Push an event with automatic state management and error handling.
    ///
    /// This helper reduces boilerplate by handling common patterns:
    /// - Sets loading state before push
    /// - Handles MainActor switching automatically
    /// - Resets loading state on completion
    /// - Logs errors automatically
    /// - Extracts error messages from server responses
    ///
    /// ## Example Usage
    /// ```swift
    /// channel?.pushEvent(
    ///     event: "submit",
    ///     payload: formData,
    ///     loading: { self.isSubmitting = $0 },
    ///     onSuccess: { [weak self] response in
    ///         self?.handleSubmitResponse(response)
    ///     },
    ///     onError: { [weak self] errorMessage in
    ///         self?.errorMessage = errorMessage
    ///         self?.reconnect()
    ///     }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - event: The event name to push
    ///   - payload: The event payload (default: empty dictionary)
    ///   - loading: Optional closure to set loading state. Receives Bool value.
    ///   - onSuccess: Called with response payload on success
    ///   - onError: Optional error handler. Receives extracted error message string.
    ///   - timeout: Request timeout in seconds (default: 5)
    func pushEvent(
        event: String,
        payload: [String: Any] = [:],
        loading: ((Bool) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        onSuccess: @escaping ([String: Any]) -> Void,
        timeout: TimeInterval = 5
    ) {
        // Set loading state on main thread
        Task { @MainActor in
            loading?(true)
        }
        
        // Perform the push operation
        Task {
            do {
                let response = try await push(event, payload, timeout: timeout)
                
                // Handle success on main thread
                await MainActor.run {
                    loading?(false)
                    onSuccess(response)
                }
                
            } catch {
                // Handle error on main thread
                await MainActor.run {
                    loading?(false)
                    DebugLogger.error("❌ \(event) failed: \(error)")
                    
                    // Extract error message from error
                    let errorMessage: String
                    if let message = (error as NSError).userInfo["message"] as? String {
                        errorMessage = message
                    } else {
                        errorMessage = "Server error"
                    }
                    
                    onError?(errorMessage)
                }
            }
        }
    }
}

// MARK: - PhoenixChannelLiveViewError

/// Errors that can occur during PhoenixChannelLiveView operations
enum PhoenixChannelLiveViewError: LocalizedError {
    case socketDisconnected
    case noChannel
    case timeout
    case pushFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .socketDisconnected:
            return "Socket is disconnected"
        case .noChannel:
            return "Channel not available"
        case .timeout:
            return "Request timed out"
        case .pushFailed(let message):
            return "Push failed: \(message)"
        }
    }
}

