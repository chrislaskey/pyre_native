import SwiftUI
import Combine

@MainActor
class URLRouter: ObservableObject {
    // Current URL
    @Published var currentURL: URL
    
    // Navigation path for SwiftUI NavigationStack
    @Published var navigationPath: [URLRoute] = []
    
    // Reload trigger for Cmd+R reconnection
    // Changing this UUID triggers .onChange observers in views
    @Published var reloadTrigger: UUID = UUID()
    
    // URL scheme
    private let scheme = "app"
    
    init() {
        self.currentURL = URL(string: "\(scheme)://\(RouterHelpers.getHomePath())")!
    }
    
    // MARK: - Navigation Methods
    
    /// Navigate to a path string
    func navigate(to path: String, queryItems: [URLQueryItem] = []) {
        guard let url = buildURL(path: path, queryItems: queryItems) else {
            print("⚠️ Invalid path: \(path)")
            return
        }
        navigate(to: url)
    }
    
    /// Navigate to a URL
    /// Uses root-only navigation: the view is rendered in the NavigationStack root,
    /// not pushed onto the navigation path. This prevents double-rendering and ensures
    /// only one view instance exists at a time.
    func navigate(to url: URL) {
        currentURL = url
        // Keep path empty - we use root-only navigation to prevent double rendering
        navigationPath = []
    }
    
    /// Replace current route
    /// Updates the current URL without adding to history.
    func replace(with url: URL) {
        currentURL = url
        // navigationPath remains empty (root-only navigation)
    }
    
    /// Go back
    /// Note: With root-only navigation, there's no automatic back stack.
    /// This method is kept for API compatibility but does nothing currently.
    /// Consider implementing a history stack if back navigation is needed.
    func pop() {
        // No-op in root-only navigation
        // Could implement manual history tracking if needed
        print("⚠️ pop() called but root-only navigation has no back stack")
    }
    
    /// Reconnect to the page
    /// Resets socket connections to ensure clean state
    /// Views observe the reloadTrigger to refresh their connections
    func reconnect() {
        print("🔄 Reconnecting connection for: \(currentURL.path)")
        
        // Reset socket connections
        // ChannelService.shared.reset()
        
        // Trigger reload by changing the UUID
        // Views observe this via .onChange(of: router.reloadTrigger)
        reloadTrigger = UUID()
    }
    
    // MARK: - URL Building
    
    private func buildURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "" // Empty host to ensure path is preserved correctly
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        return components.url
    }
    
    // MARK: - Query Parameter Helpers
    
    /// Get query parameters from current URL
    var queryParameters: [String: String] {
        guard let components = URLComponents(url: currentURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        
        return queryItems.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }
    
    /// Get specific query parameter
    func queryParameter(_ name: String) -> String? {
        queryParameters[name]
    }
}
