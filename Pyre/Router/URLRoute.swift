import Foundation

/// Wrapper around URL that provides stable identity for SwiftUI NavigationStack
struct URLRoute: Hashable, Identifiable {
    let url: URL
    
    var id: String {
        // Use path as ID for stable navigation
        url.path
    }
    
    // Path components (e.g., ["users", "register"])
    var pathComponents: [String] {
        url.pathComponents.filter { $0 != "/" }
    }
    
    // Query parameters as dictionary
    var queryParameters: [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        return queryItems.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
    
    // Hashable conformance (based on path only for navigation stability)
    func hash(into hasher: inout Hasher) {
        hasher.combine(url.path)
    }
    
    static func == (lhs: URLRoute, rhs: URLRoute) -> Bool {
        lhs.url.path == rhs.url.path
    }
}

