import Foundation

struct Connection: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var baseUrl: String

    init(name: String, baseUrl: String) {
        self.id = UUID().uuidString
        self.name = name
        self.baseUrl = baseUrl
    }

    init(id: String, name: String, baseUrl: String) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
    }
}
