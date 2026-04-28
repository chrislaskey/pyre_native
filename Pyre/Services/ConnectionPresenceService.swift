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

        // Worker capability fields — align with pyre_client's PyreClient.Config
        params["status"] = "active"
        params["available_capacity"] = NativeRunner.shared.availableCapacity
        params["backends"] = NativeRunner.shared.supportedBackends
        params["enabled_workflows"] = [String]()  // empty = all

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
                  let actionType = payload["action"] as? String,
                  let innerPayload = payload["payload"] as? [String: Any]
            else { return }

            NativeRunner.shared.dispatch(
                executionId: executionId,
                actionType: actionType,
                payload: innerPayload,
                channel: channel
            )
        }

        // Interactive loop: server sends continuation message
        newChannel.on("action_continue") { payload in
            guard let executionId = payload["execution_id"] as? String else { return }
            NativeRunner.shared.handleContinue(executionId: executionId, payload: payload)
        }

        // Interactive loop: server signals execution is finished
        newChannel.on("action_finish") { payload in
            guard let executionId = payload["execution_id"] as? String else { return }
            NativeRunner.shared.handleFinish(executionId: executionId)
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
