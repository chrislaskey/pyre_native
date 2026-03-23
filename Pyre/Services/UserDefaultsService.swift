import Foundation

class UserDefaultsService {
    private static let defaults = UserDefaults.standard

    static func get(key: String) -> Data? {
        defaults.data(forKey: key)
    }

    static func update(key: String, value: Data) {
        defaults.set(value, forKey: key)
    }

    static func delete(key: String) {
        defaults.removeObject(forKey: key)
    }
}
