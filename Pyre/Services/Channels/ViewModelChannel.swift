import Foundation
import Combine

/// Connection status for ViewModelChannel
enum ViewModelChannelStatus: Equatable {
    case disconnected
    case connecting
    case connected
}

/// Manages Phoenix channel connection lifecycle for PageViewModels.
///
/// ## Overview
/// `ViewModelChannel` encapsulates all the boilerplate for connecting to a Phoenix channel,
/// managing connection state, and handling reconnections. It uses composition to allow
/// ViewModels to focus on page-specific logic rather than connection management.
///
/// ## Usage
/// ```swift
/// class MyViewModel: ObservableObject, PageViewModel {
///     @ObservedObject var channel: ViewModelChannel
///     
///     init() {
///         let connection = ConnectionsService.getCurrentConnection()!
///         self.connection = connection
///         self.channel = ViewModelChannel(
///             path: "/my-path",
///             connection: connection
///         )
///     }
///     
///     func fetchParams(_ router: URLRouter, _ paramsFromRouter: ParamsFromRouter) {
///         // ... setup code ...
///         
///         channel.connect(
///             joinParams: paramsFromRouter.params,
///             onSuccess: { [weak self] payload in
///                 self?.handleParams(payload)
///                 
///                 // Register event handlers here
///                 self?.channel.live?.on("my_event") { payload in
///                     self?.handleMyEvent(payload)
///                 }
///             },
///             onError: { [weak self] error in
///                 DebugLogger.error("Failed to join: \(error)")
///             }
///         )
///     }
///     
///     func reconnect() {
///         // Reset page-specific state
///         myPageState = nil
///         
///         // Reconnect with same callbacks
///         channel.reconnect()
///     }
/// }
/// ```
///
/// ## Key Features
/// - **Automatic state management**: Tracks `status` (.disconnected, .connecting, .connected)
/// - **Callback preservation**: `reconnect()` automatically reuses the same callbacks
/// - **Clean reconnection**: Handles cleanup and re-registration transparently
/// - **Observable**: SwiftUI views can observe connection state changes
///
/// ## Thread Safety
/// All operations must be called from MainActor (enforced by @MainActor)
@MainActor
final class ViewModelChannel: ObservableObject {
    // MARK: - Configuration
    
    /// The channel path (e.g., "/users/log-in", "/:community")
    let path: String
    
    /// The connection this channel belongs to
    let connection: Connection
    
    /// Current channel connection status
    @Published var status: ViewModelChannelStatus = .disconnected
    
    // MARK: - Private State
    
    private var liveChannel: PhoenixChannelLiveView?
    private var cancellables = Set<AnyCancellable>()
    
    // Stored for reconnection
    private var joinParams: [String: Any] = [:]
    private var storedOnSuccess: (([String: Any]) -> Void)?
    private var storedOnError: ((Error) -> Void)?
    private var storedOnStatus: ((ViewModelChannelStatus) -> Void)?
    
    // MARK: - Initialization
    
    /// Create a new ViewModelChannel
    ///
    /// - Parameters:
    ///   - path: Channel path (e.g., "/users/log-in", "/:community")
    ///   - connection: Connection to connect to
    init(path: String, connection: Connection) {
        self.path = path
        self.connection = connection
    }
    
    // MARK: - Connection Management
    
    /// Connect to the Phoenix channel
    ///
    /// Establishes a connection to the specified channel path and registers callbacks
    /// for success and error cases. The callbacks are stored and will be automatically
    /// reused when `reconnect()` is called.
    ///
    /// ## Event Handler Registration
    /// Register additional event handlers in the `onSuccess` callback:
    /// ```swift
    /// channel.connect(
    ///     joinParams: params,
    ///     onStatus: { [weak self] status in
    ///         self?.channelStatus = status  // Update ViewModel state
    ///     },
    ///     onSuccess: { [weak self] payload in
    ///         self?.handleParams(payload)
    ///         
    ///         // Register event handlers here
    ///         self?.channel.live?.on("reload") { payload in
    ///             self?.handleReload(payload)
    ///         }
    ///     }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - joinParams: Parameters to send with channel join
    ///   - onStatus: Called when connection status changes (connecting, connected, disconnected)
    ///   - onSuccess: Called when channel successfully joins with the join payload.
    ///                Register additional event handlers here.
    ///   - onError: Called if channel join or socket connection fails
    ///   - forceNewSocket: If true, creates a new socket with fresh token even if one exists
    func connect(
        joinParams: [String: Any] = [:],
        forceNewSocket: Bool = false,
        onStatus: ((ViewModelChannelStatus) -> Void)? = nil,
        onSuccess: (([String: Any]) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        // Guard against duplicate connections
        guard liveChannel == nil else {
            DebugLogger.warning("⚠️ ViewModelChannel.connect() called but already connected to \(path)")
            return
        }
        
        guard status != .connecting else {
            DebugLogger.warning("⚠️ ViewModelChannel.connect() called but already connecting to \(path)")
            return
        }
        
        // Store params and callbacks for reconnection
        self.joinParams = joinParams
        if onStatus != nil { self.storedOnStatus = onStatus }
        if onSuccess != nil { self.storedOnSuccess = onSuccess }
        if onError != nil { self.storedOnError = onError }
        
        // Update state
        status = .connecting
        storedOnStatus?(.connecting)
        
        // Create channel (returns nil if offline mode is active)
        liveChannel = PhoenixChannelService.shared.connect(
            to: path,
            connection: connection,
            channelJoinParams: joinParams,
            forceNewSocket: forceNewSocket
        )
        
        // Handle offline mode - connection was blocked
        guard liveChannel != nil else {
            DebugLogger.debug("📴 Channel connection blocked - offline mode active")
            status = .disconnected
            storedOnStatus?(.disconnected)
            return
        }
        
        // Handle join success
        liveChannel?.onJoin { [weak self] payload in
            guard let self = self else { return }
            
            self.status = .connected
            self.storedOnStatus?(.connected)
            
            // Subscribe to disconnection events ONLY AFTER successful join.
            // This avoids race conditions where PhoenixChannelLiveView.isConnected is still
            // being updated via delayed Combine subscriptions from the socket.
            // The .dropFirst() skips the current `true` value so we only receive
            // actual disconnection events.
            self.liveChannel?.$isConnected
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] connected in
                    guard let self = self else { return }
                    
                    if !connected {
                        self.status = .disconnected
                        self.storedOnStatus?(.disconnected)
                    }
                }
                .store(in: &self.cancellables)
            
            self.storedOnSuccess?(payload)
        }

        // Handle socket error
        liveChannel?.onSocketError { [weak self] error in
            guard let self = self else { return }
            self.updateStatusAndMaybeTriggerCallbackIfChanged(.disconnected)
            self.storedOnError?(error)
        }
        
        // Handle join error
        liveChannel?.onJoinError { [weak self] error in
            guard let self = self else { return }
            self.updateStatusAndMaybeTriggerCallbackIfChanged(.disconnected)
            self.storedOnError?(error)
        }
    }

    private func updateStatusAndMaybeTriggerCallbackIfChanged(_ newStatus: ViewModelChannelStatus) {
        guard self.status != newStatus else { return }

        self.status = newStatus
        self.storedOnStatus?(newStatus)
    }
    
    /// Reconnect to the channel
    ///
    /// Cleans up the existing connection and creates a new one using the same
    /// configuration (path, connection, joinParams) and callbacks that were
    /// provided to the original `connect()` call.
    ///
    /// This means event handlers registered in `onSuccess` and the `onStatus`
    /// callback will be automatically re-registered on reconnection.
    ///
    /// ## Usage
    /// ```swift
    /// func reconnect() {
    ///     // Reset page-specific state
    ///     timestamp = nil
    ///     
    ///     // Reconnect (automatically re-registers all handlers)
    ///     channel.reconnect()
    /// }
    /// ```
    ///
    /// ## Force New Socket with Fresh Token
    /// When you need to reconnect with a fresh token (e.g., after password update):
    /// ```swift
    /// func reload() {
    ///     // Reconnect with fresh token from Keychain
    ///     channel.reconnect(forceNewSocket: true)
    /// }
    /// ```
    ///
    /// - Parameter forceNewSocket: If true, creates a new socket with fresh token from Keychain
    func reconnect(forceNewSocket: Bool = false) {
        DebugLogger.debug("🔄 ViewModelChannel reconnecting: \(path) forceNewSocket=\(forceNewSocket)")
        
        // Clean up existing connection
        cleanup()
        
        // Reconnect with stored configuration and callbacks
        connect(
            joinParams: joinParams,
            forceNewSocket: forceNewSocket,
            onStatus: storedOnStatus,
            onSuccess: storedOnSuccess,
            onError: storedOnError
        )
    }
    
    /// Clean up connection state
    ///
    /// Cancels all subscriptions and clears the channel reference.
    /// Does not disconnect the underlying socket (PhoenixChannelLiveView handles that in deinit).
    private func cleanup() {
        cancellables.removeAll()
        liveChannel = nil
        status = .disconnected
    }
    
    // MARK: - Public Helpers
    
    /// Access the underlying PhoenixChannelLiveView for advanced usage
    ///
    /// Returns `nil` if not connected. Most operations have convenience methods
    /// on `ViewModelChannel` itself (e.g., `on()`, `pushEvent()`).
    var live: PhoenixChannelLiveView? {
        return liveChannel
    }
    
    /// Register an event handler for a specific event
    ///
    /// This is a convenience wrapper around `PhoenixChannelLiveView.on()`.
    /// Typically called in the `onSuccess` callback of `connect()`.
    ///
    /// ## Example
    /// ```swift
    /// channel.connect(
    ///     joinParams: params,
    ///     onSuccess: { [weak self] payload in
    ///         self?.handleParams(payload)
    ///         
    ///         // Register event handlers
    ///         self?.channel.on("reload") { payload in
    ///             self?.handleReload(payload)
    ///         }
    ///     }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - event: Event name to listen for
    ///   - callback: Handler called when event is received
    func on(_ event: String, callback: @escaping ([String: Any]) -> Void) {
        guard let liveChannel = liveChannel else {
            DebugLogger.warning("⚠️ Cannot register handler for '\(event)': not connected to \(path)")
            return
        }
        
        liveChannel.on(event, callback)
    }
    
    /// Push an event to the channel
    ///
    /// This is a convenience wrapper around `PhoenixChannelLiveView.pushEvent()`.
    /// Automatically handles the case where the channel is not connected.
    ///
    /// - Parameters:
    ///   - event: Event name
    ///   - payload: Event payload
    ///   - loading: Called with loading state (true when starting, false when done)
    ///   - onSuccess: Called with response on success
    ///   - onError: Called with error message on failure
    func pushEvent(
        event: String,
        payload: [String: Any] = [:],
        loading: ((Bool) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        onSuccess: @escaping ([String: Any]) -> Void,
        timeout: TimeInterval = 5
    ) {
        guard let liveChannel = liveChannel else {
            DebugLogger.warning("⚠️ Cannot push event '\(event)': not connected to \(path)")
            onError?("Not connected to channel")
            return
        }
        
        liveChannel.pushEvent(
            event: event,
            payload: payload,
            loading: loading,
            onError: onError,
            onSuccess: onSuccess
        )
    }
}

