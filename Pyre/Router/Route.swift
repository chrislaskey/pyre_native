import SwiftUI

struct Route {
    let pattern: RoutePattern
    let requireCurrentUser: Bool
    let viewBuilder: (ParamsFromRouter) -> AnyView
    
    init(
        _ pattern: String,
        requireCurrentUser: Bool = false,
        @ViewBuilder view: @escaping (ParamsFromRouter) -> some View
    ) {
        self.pattern = RoutePattern(pattern)
        self.requireCurrentUser = requireCurrentUser
        self.viewBuilder = { paramsFromRouter in AnyView(view(paramsFromRouter)) }
    }
    
    func match(_ url: URL) -> RouteMatch? {
        let path = url.path.isEmpty ? "/" : url.path

        guard let params = pattern.match(path) else { return nil }
        let paramsFromRouter = ParamsFromRouter(url: url, path: path, template: pattern.pattern, params: params)
        return RouteMatch(route: self, paramsFromRouter: paramsFromRouter)
    }
}

struct RouteMatch {
    let route: Route
    let paramsFromRouter: ParamsFromRouter
}
