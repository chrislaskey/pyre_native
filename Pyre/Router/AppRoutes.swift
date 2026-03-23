import SwiftUI

struct AppRoutes: AppRoutesProtocol {
    static let routes: [Route] = [
        // Connection routes

        Route("/connections") { paramsFromRouter in ConnectionsIndexView(paramsFromRouter: paramsFromRouter) },
        Route("/connections/new") { paramsFromRouter in ConnectionsNewView(paramsFromRouter: paramsFromRouter) },
        Route("/connections/:id") { paramsFromRouter in ConnectionsEditView(paramsFromRouter: paramsFromRouter) },

        // Auth routes

        Route("/sign-in", requireCurrentConnection: true) { paramsFromRouter in SignInView(paramsFromRouter: paramsFromRouter) },
        Route("/sign-out", requireCurrentConnection: true) { paramsFromRouter in SignOutView(paramsFromRouter: paramsFromRouter) },

        // App routes

        Route("/", requireCurrentConnection: true, requireCurrentUser: true) { paramsFromRouter in HomeView(paramsFromRouter: paramsFromRouter) },
    ]
}
