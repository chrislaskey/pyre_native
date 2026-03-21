import Foundation

/// Parameters passed to a page from the router.
/// Contains both the matched URL parameters and the original path.
struct ParamsFromRouter {
    let url: URL

    /// The original URL path (e.g., "/organizations/123/log-in")
    let path: String
    
    /// The route template that matched (e.g., "/organizations/:id/log-in")
    let template: String
    
    /// Extracted route parameters (e.g., ["id": "123"])
    let params: [String: String]
    
    /// Query parameters from the URL (e.g., ["code": "abc123", "state": "xyz"])
    var queryParams: [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        return queryItems.reduce(into: [:]) { result, item in
            if let value = item.value {
                result[item.name] = value
            }
        }
    }
    
    /// Unified accessor - checks path params first, then query params
    /// This allows you to access both types of parameters with the same syntax
    subscript(key: String) -> String? {
        params[key] ?? queryParams[key]
    }
    
    /// Explicit path param accessor (when you need to distinguish from query params)
    func pathParam(_ key: String) -> String? {
        params[key]
    }
    
    /// Explicit query param accessor (when you need to distinguish from path params)
    func queryParam(_ key: String) -> String? {
        queryParams[key]
    }
}
