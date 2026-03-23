import Foundation
import Combine

/// Internal socket pool manager for a single Connection.
/// Maintains long-lived WebSocket connections with automatic reference counting.
///
/// ## Architecture
/// - One SocketPool per Connection
/// - Sockets are keyed by their WebSocket URL (derived from channel path)
/// - Reference counting ensures sockets stay alive while channels need them
/// - Sockets are disconnected when ref count hits zero
///
/// ## Thread Safety
/// All operations must be called from MainActor (enforced by @MainActor)
@MainActor
final class PhoenixSocketPool {
    let connection: Connection
    
    /// Active socket connections with their reference counts
    private var sockets: [String: PooledSocket] = [:]
    
    init(connection: Connection) {
        self.connection = connection
        DebugLogger.debug("📦 SocketPool created for: \(connection.name)")
    }
    
    deinit {
        // Capture value for async context
        let name = connection.name
        Task { @MainActor in
            DebugLogger.debug("📦 SocketPool destroyed for: \(name)")
        }
    }
    
    // MARK: - Socket Access
    
    /// Get or create a socket for the given channel path.
    /// Automatically increments reference count.
    ///
    /// - Parameters:
    ///   - channelPath: Channel path (e.g., "/users/log-in")
    ///   - token: Optional auth token
    ///   - forceNew: If true, disconnects existing socket and creates a new one with fresh token
    /// - Returns: The socket (connected or connecting)
    func acquire(channelPath: String, token: String? = nil, forceNew: Bool = false) -> PhoenixSocket {
        let url = PhoenixSocket.buildWebSocketURL(connection: connection, channelPath: channelPath)
        
        // Check for existing socket
        if let pooled = sockets[url], !forceNew {
            // Verify socket is still usable
            if pooled.socket.isConnected || pooled.isConnecting {
                pooled.refCount += 1
                DebugLogger.debug("📊 Socket acquired (reused): \(url) refs=\(pooled.refCount)")
                return pooled.socket
            } else {
                // Stale socket - remove and create new
                DebugLogger.warning("⚠️ Stale socket found, replacing: \(url)")
                pooled.socket.disconnect()
                sockets[url] = nil
            }
        } else if let pooled = sockets[url], forceNew {
            // Force new socket - disconnect old one
            DebugLogger.info("🔄 Forcing new socket with fresh token: \(url)")
            pooled.socket.disconnect()
            sockets[url] = nil
        }
        
        // Create new socket
        var params: [String: Any] = [:]
        if let token = token {
            params["encoded_identity_token"] = token
        }
        
        let socket = PhoenixSocket(url: url, params: params)
        let pooled = PooledSocket(socket: socket)
        pooled.refCount = 1
        pooled.isConnecting = true
        sockets[url] = pooled
        
        // Connect and track connection state
        socket.connect()
        
        // Mark as no longer "connecting" once we get a connection result
        socket.$isConnected
            .dropFirst() // Skip initial false value
            .first() // Only need first change
            .sink { [weak pooled] _ in
                pooled?.isConnecting = false
            }
            .store(in: &pooled.cancellables)
        
        DebugLogger.debug("📊 Socket acquired (new): \(url) refs=1")
        return socket
    }
    
    /// Release a socket reference for the given channel path.
    /// Decrements reference count and disconnects if no longer needed.
    /// Only releases if the provided socket matches the one in the pool.
    ///
    /// - Parameters:
    ///   - channelPath: Channel path
    ///   - socket: The specific socket instance to release (must match pool's socket)
    func release(channelPath: String, socket: PhoenixSocket) {
        let url = PhoenixSocket.buildWebSocketURL(connection: connection, channelPath: channelPath)

        guard let pooled = sockets[url] else {
            // Socket not in pool - might have been cleared by reset()
            DebugLogger.debug("📊 Release skipped - socket not in pool: \(url)")
            return
        }
        
        // Only release if this is the SAME socket instance
        // This prevents stale async releases from affecting new sockets
        guard pooled.socket === socket else {
            DebugLogger.debug("📊 Release skipped - socket instance mismatch (stale release)")
            return
        }
        
        pooled.refCount -= 1
        DebugLogger.debug("📊 Socket released: \(url) refs=\(pooled.refCount)")
        
        if pooled.refCount <= 0 {
            DebugLogger.debug("🔌 Socket no longer needed, disconnecting: \(url)")
            pooled.socket.disconnect()
            sockets[url] = nil
        }
    }
    
    /// Get socket for a channel path without affecting reference count.
    /// Useful for checking connection state.
    func peek(channelPath: String) -> PhoenixSocket? {
        let url = PhoenixSocket.buildWebSocketURL(connection: connection, channelPath: channelPath)
        return sockets[url]?.socket
    }
    
    // MARK: - Pool Management
    
    /// Disconnect all sockets in this pool.
    /// Called when user logs out or organization is removed.
    func disconnectAll() {
        DebugLogger.debug("🔌 Disconnecting all sockets for: \(connection.name)")
        
        for (_, pooled) in sockets {
            pooled.socket.disconnect()
        }
        sockets.removeAll()
    }
    
    /// Get debug status of all sockets
    var status: String {
        if sockets.isEmpty {
            return "no active sockets"
        }
        return sockets.map { url, pooled in
            "\(url): refs=\(pooled.refCount) connected=\(pooled.socket.isConnected)"
        }.joined(separator: ", ")
    }
}

// MARK: - PooledSocket

/// Internal wrapper for tracking socket state in the pool
private final class PooledSocket {
    let socket: PhoenixSocket
    var refCount: Int = 0
    var isConnecting: Bool = false
    var cancellables = Set<AnyCancellable>()
    
    init(socket: PhoenixSocket) {
        self.socket = socket
    }
}

