import Foundation

class ConnectionsService {
    private static let connectionsKey = "connections"
    private static let currentConnectionIdKey = "connections_current_id"

    // MARK: - All Connections

    static func list() -> [String: Connection] {
        guard let data = UserDefaultsService.get(key: connectionsKey) else {
            return [:]
        }
        let connections = try? JSONDecoder().decode([String: Connection].self, from: data)
        return connections ?? [:]
    }

    static func get(id: String) -> Connection? {
        list()[id]
    }

    /// Creates a new connection. Returns false if a connection with the same name and baseUrl already exists.
    @discardableResult
    static func create(_ connection: Connection) -> Bool {
        var connections = list()
        let duplicate = connections.values.contains { existing in
            existing.name == connection.name && existing.baseUrl == connection.baseUrl
        }
        if duplicate { return false }

        connections[connection.id] = connection
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaultsService.update(key: connectionsKey, value: data)
        }
        return true
    }

    static func update(_ connection: Connection) {
        var connections = list()
        connections[connection.id] = connection
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaultsService.update(key: connectionsKey, value: data)
        }
    }

    static func delete(id: String) {
        var connections = list()
        connections.removeValue(forKey: id)
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaultsService.update(key: connectionsKey, value: data)
        }

        if getCurrentConnectionId() == id {
            if let next = connections.values.first {
                updateCurrentConnectionId(next.id)
            } else {
                deleteCurrentConnectionId()
            }
        }
    }

    // MARK: - Current Connection

    static func getCurrentConnectionId() -> String? {
        guard let data = UserDefaultsService.get(key: currentConnectionIdKey),
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        return id
    }

    static func updateCurrentConnectionId(_ id: String) {
        if let data = id.data(using: .utf8) {
            UserDefaultsService.update(key: currentConnectionIdKey, value: data)
        }
    }

    static func deleteCurrentConnectionId() {
        UserDefaultsService.delete(key: currentConnectionIdKey)
    }

    static func getCurrentConnection() -> Connection? {
        guard let id = getCurrentConnectionId() else { return nil }
        return get(id: id)
    }
}
