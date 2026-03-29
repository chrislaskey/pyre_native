import Foundation
import Combine

/// Maintains a persistent Phoenix channel connection to report this app's
/// presence to the server. Reconnects automatically when the active
/// connection changes.
@MainActor
final class ConnectionPresenceService: ObservableObject {
    @Published private(set) var isConnected: Bool = false

    private var channel: PhoenixChannelLiveView?
    private var currentConnectionId: String?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: ConnectionsService.currentConnectionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconnectIfNeeded()
            }
            .store(in: &cancellables)

        reconnectIfNeeded()
    }

    // MARK: - Private

    private func reconnectIfNeeded() {
        guard let connection = ConnectionsService.getCurrentConnection() else {
            disconnect()
            return
        }

        // Already connected to this connection
        if currentConnectionId == connection.id { return }

        disconnect()
        connect(to: connection)
    }

    private func connect(to connection: Connection) {
        let info = ConnectionInfo.current()
        var params = info.toDictionary()
        params["connection_id"] = info.connectionId

        let newChannel = PhoenixChannelService.shared.connect(
            to: "pyre:connections",
            connection: connection,
            channelJoinParams: params
        )

        guard let newChannel else { return }

        newChannel.$isJoined
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        // Handle actions dispatched from the server
        newChannel.on("action") { [weak newChannel] payload in
            guard let channel = newChannel,
                  let executionId = payload["execution_id"] as? String,
                  let type = payload["type"] as? String,
                  let innerPayload = payload["payload"] as? [String: Any]
            else { return }

            switch type {
            case "execute_commands":
                guard let commands = innerPayload["commands"] as? [String] else { return }
                #if os(macOS)
                RemoteCommandService.shared.execute(
                    commands: commands,
                    executionId: executionId,
                    channel: channel
                )
                #else
                DebugLogger.warning("execute_commands not supported on this platform")
                #endif
            default:
                DebugLogger.warning("Unknown action type: \(type)")
            }
        }

        channel = newChannel
        currentConnectionId = connection.id
    }

    private func disconnect() {
        channel = nil
        currentConnectionId = nil
        isConnected = false
    }
}
