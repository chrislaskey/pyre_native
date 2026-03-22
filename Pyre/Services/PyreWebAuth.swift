import Foundation
import WebKit

class PyreWebAuth {
    enum CookieType: String {
        case accessCookie = "pyre_web_access_cookie"
        case refreshCookie = "pyre_web_refresh_cookie"
    }

    // MARK: - CRUD by Key

    static func get(_ key: String) -> String? {
        return KeychainService.get(key: key)
    }

    @discardableResult
    static func upsert(_ key: String, value: String) -> Bool {
        return KeychainService.save(key: key, value: value)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        return KeychainService.delete(key: key)
    }

    // MARK: - CRUD by CookieType

    static func get(type: CookieType) -> String? {
        return get(type.rawValue)
    }

    @discardableResult
    static func upsert(type: CookieType, value: String) -> Bool {
        return upsert(type.rawValue, value: value)
    }

    @discardableResult
    static func delete(type: CookieType) -> Bool {
        return delete(type.rawValue)
    }

    // MARK: - WebView Management

    static func clearWebViewCookies() async {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: dataTypes)
        await dataStore.removeData(ofTypes: dataTypes, for: records)
        DebugLogger.info("Cleared WebView cookies and data")
    }
}
