import SwiftUI

struct RouterView: View {
    @EnvironmentObject var router: URLRouter
    
    var body: some View {
        // Root-only navigation: currentURL drives the view shown in the root position.
        // navigationPath is kept empty to prevent double-rendering issues.
        // This ensures only ONE view instance exists at a time.
        NavigationStack {
            routeView(for: router.currentURL)
                // Use URL path as view identity to force recreation when navigating
                // between different paths that match the same route template
                // (e.g., /hello/one → /hello/two both matching /hello/:id)
                .id(router.currentURL.path)
                .navigationBarBackButtonHidden(true)
        }
        .onChange(of: router.currentURL) { _, newURL in
            handleRouteChange(newURL)
        }
    }
    
    @ViewBuilder
    private func routeView(for url: URL) -> some View {
        if let match = match(url: url) {
            let route = match.route
            let hasCurrentUser = false
            let hasCurrentConnection = ConnectionsService.getCurrentConnectionId() != nil

            if route.requireCurrentUser && !hasCurrentUser {
                UnauthorizedView()
            } else if route.requireCurrentConnection && !hasCurrentConnection {
                RedirectView(to: "/connections", router: router)
            } else {
                route.viewBuilder(match.paramsFromRouter)
            }
        } else {
            NotFoundView()
        }
    }

    /// Match a path against all registered routes
    /// Returns the first matching route with extracted parameters
    private func match(url: URL) -> RouteMatch? {
        guard !url.path.isEmpty else { return nil }
        
        // Don't match paths with trailing slashes (except root "/")
        guard url.path == "/" || !url.path.hasSuffix("/") else { return nil }
        
        for route in AppRoutes.routes {
            if let match = route.match(url) {
                return match
            }
        }
        
        return nil
    }
    
    private func handleRouteChange(_ url: URL) {
        guard let match = match(url: url) else {
            return
        }

        print("📍 Route: \(match.paramsFromRouter.path)")
        print("🔒 Current user required: \(match.route.requireCurrentUser)")
        print("🔗 Current connection required: \(match.route.requireCurrentConnection)")
    }
}
