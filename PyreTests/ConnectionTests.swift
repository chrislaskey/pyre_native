import Testing
@testable import Pyre

struct ConnectionTests {

    @Test func initWithAutoId() {
        let connection = Connection(name: "Dev Server", baseUrl: "https://dev.example.com")

        #expect(!connection.id.isEmpty)
        #expect(connection.name == "Dev Server")
        #expect(connection.baseUrl == "https://dev.example.com")
    }

    @Test func initWithExplicitId() {
        let connection = Connection(id: "custom-id", name: "Staging", baseUrl: "https://staging.example.com")

        #expect(connection.id == "custom-id")
        #expect(connection.name == "Staging")
        #expect(connection.baseUrl == "https://staging.example.com")
    }

    @Test func autoIdIsUUID() {
        let connection = Connection(name: "Test", baseUrl: "https://example.com")

        #expect(UUID(uuidString: connection.id) != nil)
    }

    @Test func autoIdIsUnique() {
        let a = Connection(name: "A", baseUrl: "https://a.com")
        let b = Connection(name: "B", baseUrl: "https://b.com")

        #expect(a.id != b.id)
    }

    @Test func codableRoundTrip() throws {
        let original = Connection(id: "abc-123", name: "Production", baseUrl: "https://prod.example.com")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Connection.self, from: data)

        #expect(decoded == original)
    }

    @Test func equatable() {
        let a = Connection(id: "same-id", name: "Server", baseUrl: "https://example.com")
        let b = Connection(id: "same-id", name: "Server", baseUrl: "https://example.com")
        let c = Connection(id: "different-id", name: "Server", baseUrl: "https://example.com")

        #expect(a == b)
        #expect(a != c)
    }
}
