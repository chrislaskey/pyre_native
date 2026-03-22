import Foundation
import Security

/// Service for securely storing and retrieving user authentication tokens using iOS Keychain
/// Supports multi-tenant architecture where users can connect to different organizations
class KeychainService {
    // MARK: - Configuration
    
    /// The service identifier for grouping keychain items
    private static let service = Bundle.main.bundleIdentifier!
    
    // MARK: - Generic Keychain Operations
    
    /// Save a string value to the Keychain
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    /// - Returns: True if successful, false otherwise
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        
        let lookupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let existing = SecItemCopyMatching(lookupQuery as CFDictionary, nil)
        
        if existing == errSecSuccess {
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            let status = SecItemUpdate(lookupQuery as CFDictionary, updateAttributes as CFDictionary)
            return status == errSecSuccess
        } else {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            return status == errSecSuccess
        }
    }
    
    /// Retrieve a string value from the Keychain
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The string value if it exists, nil otherwise
    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    /// Delete a value from the Keychain
    /// - Parameter key: The key to delete
    /// - Returns: True if successful or item doesn't exist, false otherwise
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Success if deleted or if item didn't exist
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Debugging (Development Only)
    
    /// Delete all items for this service from the Keychain
    /// ⚠️ Use only for development/testing
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
