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

        channel = newChannel
        currentConnectionId = connection.id
    }

    private func disconnect() {
        channel = nil
        currentConnectionId = nil
        isConnected = false
    }
}
