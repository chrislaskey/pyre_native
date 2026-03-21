import SwiftUI

struct AppRoutes: AppRoutesProtocol {
    static let routes: [Route] = [
        // Auth routes

        Route("/sign-in") { paramsFromRouter in Home(paramsFromRouter: paramsFromRouter) },
        Route("/sign-out") { paramsFromRouter in Home(paramsFromRouter: paramsFromRouter) },

        // App routes

        // Route("/", requireCurrentUser: true) { paramsFromRouter in Home(paramsFromRouter: paramsFromRouter) },
        Route("/") { paramsFromRouter in Home(paramsFromRouter: paramsFromRouter) },
    ]
}
