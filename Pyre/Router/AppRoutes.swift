import SwiftUI

struct AppRoutes: AppRoutesProtocol {
    static let routes: [Route] = [
        // Auth routes

        Route("/sign-in") { paramsFromRouter in SignInView(paramsFromRouter: paramsFromRouter) },
        Route("/sign-out") { paramsFromRouter in HomeView(paramsFromRouter: paramsFromRouter) },

        // App routes

        Route("/", requireCurrentUser: true) { paramsFromRouter in HomeView(paramsFromRouter: paramsFromRouter) },
    ]
}
