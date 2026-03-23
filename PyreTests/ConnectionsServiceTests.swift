import Testing
import Foundation
@testable import Pyre

struct ConnectionsServiceTests {

    init() {
        // Clean slate before each test
        UserDefaults.standard.removeObject(forKey: "connections")
        UserDefaults.standard.removeObject(forKey: "connections_current_id")
    }

    // MARK: - list

    @Test func listReturnsEmptyWhenNoConnections() {
        let result = ConnectionsService.list()
        #expect(result.isEmpty)
    }

    // MARK: - create & get

    @Test func createAndGetConnection() {
        let connection = Connection(id: "test-1", name: "Dev", baseUrl: "https://dev.example.com")

        ConnectionsService.create(connection)
        let fetched = ConnectionsService.get(id: "test-1")

        #expect(fetched == connection)
    }

    @Test func createMultipleConnections() {
        let a = Connection(id: "a", name: "Alpha", baseUrl: "https://alpha.com")
        let b = Connection(id: "b", name: "Beta", baseUrl: "https://beta.com")

        ConnectionsService.create(a)
        ConnectionsService.create(b)

        let all = ConnectionsService.list()
        #expect(all.count == 2)
        #expect(all["a"] == a)
        #expect(all["b"] == b)
    }

    @Test func createReturnsTrueOnSuccess() {
        let connection = Connection(id: "new", name: "New", baseUrl: "https://new.com")
        let result = ConnectionsService.create(connection)
        #expect(result == true)
    }

    @Test func createRejectsDuplicateNameAndBaseUrl() {
        let first = Connection(id: "first", name: "Server", baseUrl: "https://example.com")
        let duplicate = Connection(id: "second", name: "Server", baseUrl: "https://example.com")

        let firstResult = ConnectionsService.create(first)
        let duplicateResult = ConnectionsService.create(duplicate)

        #expect(firstResult == true)
        #expect(duplicateResult == false)
        #expect(ConnectionsService.list().count == 1)
        #expect(ConnectionsService.get(id: "second") == nil)
    }

    @Test func createAllowsSameNameDifferentUrl() {
        let a = Connection(id: "a", name: "Server", baseUrl: "https://a.com")
        let b = Connection(id: "b", name: "Server", baseUrl: "https://b.com")

        #expect(ConnectionsService.create(a) == true)
        #expect(ConnectionsService.create(b) == true)
        #expect(ConnectionsService.list().count == 2)
    }

    @Test func createAllowsSameUrlDifferentName() {
        let a = Connection(id: "a", name: "Alpha", baseUrl: "https://example.com")
        let b = Connection(id: "b", name: "Beta", baseUrl: "https://example.com")

        #expect(ConnectionsService.create(a) == true)
        #expect(ConnectionsService.create(b) == true)
        #expect(ConnectionsService.list().count == 2)
    }

    // MARK: - update

    @Test func updateExistingConnection() {
        let original = Connection(id: "x", name: "Original", baseUrl: "https://original.com")
        ConnectionsService.create(original)

        let updated = Connection(id: "x", name: "Updated", baseUrl: "https://updated.com")
        ConnectionsService.update(updated)

        let fetched = ConnectionsService.get(id: "x")
        #expect(fetched?.name == "Updated")
        #expect(fetched?.baseUrl == "https://updated.com")
        #expect(ConnectionsService.list().count == 1)
    }

    @Test func updateDoesNotCheckForDuplicates() {
        let a = Connection(id: "a", name: "Server", baseUrl: "https://example.com")
        let b = Connection(id: "b", name: "Other", baseUrl: "https://other.com")
        ConnectionsService.create(a)
        ConnectionsService.create(b)

        // Update b to match a's name+url — should succeed (update skips duplicate check)
        let bUpdated = Connection(id: "b", name: "Server", baseUrl: "https://example.com")
        ConnectionsService.update(bUpdated)

        #expect(ConnectionsService.get(id: "b")?.name == "Server")
    }

    // MARK: - get

    @Test func getReturnsNilForMissingId() {
        let result = ConnectionsService.get(id: "nonexistent")
        #expect(result == nil)
    }

    // MARK: - delete

    @Test func deleteRemovesConnection() {
        let connection = Connection(id: "del-1", name: "ToDelete", baseUrl: "https://delete.com")
        ConnectionsService.create(connection)
        #expect(ConnectionsService.get(id: "del-1") != nil)

        ConnectionsService.delete(id: "del-1")

        #expect(ConnectionsService.get(id: "del-1") == nil)
        #expect(ConnectionsService.list().isEmpty)
    }

    @Test func deleteLeavesOtherConnections() {
        let a = Connection(id: "keep", name: "Keep", baseUrl: "https://keep.com")
        let b = Connection(id: "remove", name: "Remove", baseUrl: "https://remove.com")
        ConnectionsService.create(a)
        ConnectionsService.create(b)

        ConnectionsService.delete(id: "remove")

        #expect(ConnectionsService.list().count == 1)
        #expect(ConnectionsService.get(id: "keep") == a)
    }

    @Test func deleteNonexistentIdIsNoOp() {
        let connection = Connection(id: "safe", name: "Safe", baseUrl: "https://safe.com")
        ConnectionsService.create(connection)

        ConnectionsService.delete(id: "ghost")

        #expect(ConnectionsService.list().count == 1)
    }

    // MARK: - Current Connection

    @Test func currentConnectionIdDefaultsToNil() {
        #expect(ConnectionsService.getCurrentConnectionId() == nil)
    }

    @Test func updateAndGetCurrentConnectionId() {
        ConnectionsService.updateCurrentConnectionId("conn-1")

        #expect(ConnectionsService.getCurrentConnectionId() == "conn-1")
    }

    @Test func deleteCurrentConnectionId() {
        ConnectionsService.updateCurrentConnectionId("conn-1")
        ConnectionsService.deleteCurrentConnectionId()

        #expect(ConnectionsService.getCurrentConnectionId() == nil)
    }

    @Test func getCurrentConnectionReturnsMatchingConnection() {
        let connection = Connection(id: "current", name: "Current", baseUrl: "https://current.com")
        ConnectionsService.create(connection)
        ConnectionsService.updateCurrentConnectionId("current")

        let result = ConnectionsService.getCurrentConnection()
        #expect(result == connection)
    }

    @Test func getCurrentConnectionReturnsNilWhenNoIdSet() {
        let connection = Connection(id: "orphan", name: "Orphan", baseUrl: "https://orphan.com")
        ConnectionsService.create(connection)

        #expect(ConnectionsService.getCurrentConnection() == nil)
    }

    @Test func getCurrentConnectionReturnsNilWhenIdDoesNotMatch() {
        ConnectionsService.updateCurrentConnectionId("missing")

        #expect(ConnectionsService.getCurrentConnection() == nil)
    }

    // MARK: - delete clears current connection

    @Test func deletingCurrentConnectionClearsCurrentId() {
        let connection = Connection(id: "active", name: "Active", baseUrl: "https://active.com")
        ConnectionsService.create(connection)
        ConnectionsService.updateCurrentConnectionId("active")

        ConnectionsService.delete(id: "active")

        #expect(ConnectionsService.getCurrentConnectionId() == nil)
    }

    @Test func deletingNonCurrentConnectionPreservesCurrentId() {
        let a = Connection(id: "current", name: "Current", baseUrl: "https://current.com")
        let b = Connection(id: "other", name: "Other", baseUrl: "https://other.com")
        ConnectionsService.create(a)
        ConnectionsService.create(b)
        ConnectionsService.updateCurrentConnectionId("current")

        ConnectionsService.delete(id: "other")

        #expect(ConnectionsService.getCurrentConnectionId() == "current")
    }
}
