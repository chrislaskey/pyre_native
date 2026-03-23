import Testing
import Foundation
@testable import Pyre

struct UserDefaultsServiceTests {
    private let testKey = "test_user_defaults_service_key"

    init() {
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    @Test func getReturnsNilForMissingKey() {
        #expect(UserDefaultsService.get(key: testKey) == nil)
    }

    @Test func updateAndGet() {
        let data = "hello".data(using: .utf8)!

        UserDefaultsService.update(key: testKey, value: data)
        let result = UserDefaultsService.get(key: testKey)

        #expect(result == data)

        UserDefaultsService.delete(key: testKey)
    }

    @Test func deleteRemovesValue() {
        let data = "to-delete".data(using: .utf8)!
        UserDefaultsService.update(key: testKey, value: data)
        #expect(UserDefaultsService.get(key: testKey) != nil)

        UserDefaultsService.delete(key: testKey)

        #expect(UserDefaultsService.get(key: testKey) == nil)
    }

    @Test func deleteNonexistentKeyIsNoOp() {
        UserDefaultsService.delete(key: testKey)
        #expect(UserDefaultsService.get(key: testKey) == nil)
    }

    @Test func updateOverwritesPreviousValue() {
        let first = "first".data(using: .utf8)!
        let second = "second".data(using: .utf8)!

        UserDefaultsService.update(key: testKey, value: first)
        UserDefaultsService.update(key: testKey, value: second)

        let result = UserDefaultsService.get(key: testKey)
        #expect(result == second)

        UserDefaultsService.delete(key: testKey)
    }
}
