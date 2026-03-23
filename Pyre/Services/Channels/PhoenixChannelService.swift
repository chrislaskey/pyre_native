import Foundation
import Combine

/// Central service for Phoenix channel connections.
///
/// ## Overview
/// `ChannelService` is the main entry point for connecting to Phoenix channels.
/// It manages socket pools per connection and provides a simple API for Views/ViewModels.
///
/// ## Usage
/// ```swift
/// // In a ViewModel
/// let channel = ChannelService.shared.connect(
///     to: "/users/log-in",
///     connection: MyConnection,
///     token: authToken
/// )
///
/// // LiveChannel handles its own lifecycle - no cleanup needed!
/// ```
///
/// ## Multi-Tenant Support
/// Sockets are pooled per connection. When switching connections:
/// - Existing sockets remain connected (for quick switching back)
/// - New connections use the appropriate connections's pool
/// - Pools are cleaned up when connections are removed
///
/// ## Thread Safety
/// All operations run on MainActor.
@MainActor
final class PhoenixChannelService: ObservableObject {
    /// Shared singleton instance
    static let shared = PhoenixChannelService()
    
    /// Socket pools per connections (keyed by connections ID)
    private let poolingEnabled = true
    private var pools: [String: PhoenixSocketPool] = [:]
    
    private init() {
        DebugLogger.section("CHANNEL SERVICE")
        DebugLogger.info("🌍 ChannelService initialized")
    }
    
    // MARK: - Offline Mode
    
    /// Check if offline mode is active (from any source)
    ///
    /// Currently checks:
    /// - User toggle (device-specific, persists through reboots)
    var isOfflineMode: Bool {
        // TODO: Update this when offline mode toggle is implemented
        return false
    }
    
    /// Enable offline mode and disconnect all existing connections
    func goOffline() {
        // TODO: write this to a UserDefaults value
        disconnectAll()
    }
    
    /// Disable offline mode (connections can be re-established)
    func goOnline() {
        // TODO: write this to a UserDefaults value
        // Note: Views/ViewModels are responsible for reconnecting
    }
    
    /// Toggle offline mode
    func toggleOfflineMode() {
        if isOfflineMode {
            goOnline()
        } else {
            goOffline()
        }
    }
    
    // MARK: - Connection API
    
    /// Connect to a Phoenix channel.
    ///
    /// This is the primary API for ViewModels to establish channel connections.
    /// The returned `LiveChannel` manages its own lifecycle - when it's deallocated,
    /// it automatically releases its socket reference.
    ///
    /// Returns `nil` if offline mode is active.
    ///
    /// - Parameters:
    ///   - path: Channel path (e.g., "/users/log-in", "/")
    ///   - connection: The connection to connect to
    ///   - channelJoinParams: Parameters to send with channel join
    ///   - forceNewSocket: If true, creates a new socket with fresh token even if one exists
    /// - Returns: A `LiveChannel` that manages the connection, or `nil` if offline
    func connect(
        to path: String,
        connection: Connection,
        channelJoinParams: [String: Any] = [:],
        forceNewSocket: Bool = false
    ) -> PhoenixChannelLiveView? {
        // Block connections in offline mode
        guard !isOfflineMode else {
            DebugLogger.warning("📴 Connection blocked - offline mode active")
            return nil
        }
        
        DebugLogger.debug("📡 Connecting to channel: \(path) @ \(connection.name)")
        
        let token = PyreWebAuth.get(type: .refreshCookie) ?? PyreWebAuth.get(type: .accessCookie)
        let pool = getOrCreatePool(for: connection)
        let socket = pool.acquire(channelPath: path, token: token, forceNew: forceNewSocket)
        
        // Create LiveChannel with release callback
        // IMPORTANT: Capture the socket instance, not just the path, to avoid
        // releasing a different socket if a new one was created for the same path
        let channel = PhoenixChannelLiveView(
            path: path,
            connection: connection,
            socket: socket,
            joinParams: channelJoinParams,
            onRelease: { [weak self, weak socket] in
                guard let socket = socket else { return }
                Task { @MainActor in
                    self?.releaseSocket(for: connection, channelPath: path, socket: socket)
                }
            }
        )
        
        return channel
    }
    
    /// Create a one-off socket connection (not pooled).
    ///
    /// Use this for special cases like connecting to a new/unknown connection
    /// before it's been added to the app. The socket is not pooled and the caller
    /// is responsible for disconnecting it.
    ///
    /// - Parameters:
    ///   - url: Full WebSocket URL
    ///   - params: Socket params
    /// - Returns: A PhoenixSocket (caller manages lifecycle)
    func createSocket(url: String, params: [String: Any] = [:]) -> PhoenixSocket {
        DebugLogger.debug("🔌 Creating standalone socket: \(url)")
        let socket = PhoenixSocket(url: url, params: params)
        socket.connect()
        return socket
    }
    
    // MARK: - Pool Management
    
    /// Reset all sockets for a specific connection.
    /// Useful after sign out or when recovering from connection issues.
    ///
    /// - Parameter connection: The connection to reset
    func reset(connection: Connection) {
        DebugLogger.section("RESET CONNECTION")
        DebugLogger.info("🔄 Resetting sockets for: \(connection.name)")
        
        if let pool = pools[connection.id] {
            pool.disconnectAll()
            pools[connection.id] = nil
        }
    }
    
    /// Remove an connection's socket pool entirely.
    /// Called when an connection is deleted from the app.
    ///
    /// - Parameter connectionId: ID of the connection to remove
    func removeConnection(_ connectionId: String) {
        DebugLogger.debug("🗑️ Removing connection pool: \(connectionId)")
        
        if let pool = pools[connectionId] {
            pool.disconnectAll()
            pools[connectionId] = nil
        }
    }
    
    /// Disconnect all sockets across all connections.
    /// Typically only used for testing or app termination.
    func disconnectAll() {
        DebugLogger.info("🔌 Disconnecting ALL connections")
        
        for (_, pool) in pools {
            pool.disconnectAll()
        }
        pools.removeAll()
    }
    
    // MARK: - Debug
    
    /// Get connection status for debugging
    var status: String {
        if pools.isEmpty {
            return "No active pools"
        }
        
        return pools.map { orgId, pool in
            "[\(orgId)]: \(pool.status)"
        }.joined(separator: "\n")
    }
    
    // MARK: - Private
    
    private func getOrCreatePool(for connection: Connection) -> PhoenixSocketPool {
        if poolingEnabled, let pool = pools[connection.id] {
            return pool
        }
        
        let pool = PhoenixSocketPool(connection: connection)

        if poolingEnabled {
            pools[connection.id] = pool
        }

        return pool
    }
    
    private func releaseSocket(for connection: Connection, channelPath: String, socket: PhoenixSocket) {
        guard let pool = pools[connection.id] else {
            DebugLogger.warning("⚠️ No pool found for release: \(connection.name)")
            return
        }
        
        pool.release(channelPath: channelPath, socket: socket)
    }
}

