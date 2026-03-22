import Foundation

class RouterHelpers {
    /// Get the home path
    static func getHomePath() -> String {
        return "/"
    }

    static func getSignInPath() -> String {
        return "/sign-in"
    }

    /// Get route path
    ///
    /// Checks with RouteRegistry
    ///
    /// - If an exact match is found in the registry, it returns the path as is.
    /// - If a path is not found for any option, returns the original path with a warning
    ///
    /// Parameters:
    /// - path: String value
    /// - params: Optional dictionary of parameters to fill in the path template
    ///
    /// Examples:
    /// - getPath("/organizations/new") -> "/organizations/new"
    /// - getPath("/organizations/:id", ["id": "default"]) -> "/organizations/default"
    ///
    /// Returns the path with parameters filled in
    static func getPath(_ path: String, _ params: [String: Any] = [:]) -> String {
        let pathExists = AppRoutes.routes.first(where: { $0.pattern.pattern == path }) != nil

        if pathExists {
            return getPathFromTemplate(path, params)
        } else {
            DebugLogger.warning("🚫 Route in `getPath` not found: \(path)")
            return path
        }
    }

    /// Get the path from a template and params
    ///
    /// - Parameter template: The template to use
    /// - Parameter params: The params to use
    ///
    /// Returns the path
    static func getPathFromTemplate(_ template: String, _ params: [String: Any]) -> String {
        var path = template

        for (key, value) in params {
            path = path.replacingOccurrences(of: ":\(key)", with: String(describing: value))
        }

        return path
    }

    // MARK: - Universal Links
    //
    // Universal Link handling is pure routing - no business logic.
    // Each handler parses the URL and navigates to the appropriate callback route.
    // The callback Views and their ViewModels handle the actual business logic.

    static func handleUniversalLink(_ url: URL, router: URLRouter) {
        DebugLogger.info("📎 Received Universal Link: \(url)")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            DebugLogger.error("❌ Failed to parse universal link URL")
            return
        }
        
        let queryItems = components.queryItems ?? []

        DebugLogger.info("📍 Path: \(url.path)")
        DebugLogger.info("📋 Query items: \(queryItems.map { "\($0.name)=\($0.value ?? "")" })")

        // Navigate with query items preserved
        router.navigate(to: url.path, queryItems: queryItems)
    }
}
