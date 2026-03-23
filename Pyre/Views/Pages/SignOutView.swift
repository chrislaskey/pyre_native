import SwiftUI
import Foundation
import Combine

// MARK: - SignOutViewModel

class SignOutViewModel: ObservableObject, PageViewModel {
    private(set) var router: URLRouter?
    private(set) var paramsFromRouter: ParamsFromRouter?

    init() {}
    
    func mount(_ paramsFromRouter: ParamsFromRouter, _ router: URLRouter) {
        self.router = router
        self.paramsFromRouter = paramsFromRouter

        handleParams()
    }
    
    func handleParams(_ payload: [String: Any] = [:]) {

    }

    func reload() {
        handleParams()
    }

    func signOut() {
        PyreWebAuth.delete(type: .accessCookie)
        PyreWebAuth.delete(type: .refreshCookie)

        Task {
            await PyreWebAuth.clearWebViewCookies()

            await MainActor.run {
                self.router!.navigate(to: RouterHelpers.getSignInPath())
            }
        }
    }
}

// MARK: - SignOutView

struct SignOutView: View {
    @EnvironmentObject var router: URLRouter

    @StateObject private var viewModel = SignOutViewModel()
    @State private var paramsFromRouter: ParamsFromRouter
    @State private var handledFirstOnAppear = false

    init(paramsFromRouter: ParamsFromRouter) {
        self.paramsFromRouter = paramsFromRouter
    }

    var body: some View {
        Color.clear
            .withPageReloadable(viewModel: viewModel)
            .onAppear {
                if !handledFirstOnAppear {
                    viewModel.mount(paramsFromRouter, router)
                    viewModel.signOut()
                    handledFirstOnAppear = true
                }
            }
            .onDisappear {
                handledFirstOnAppear = false
            }
    }
}

#Preview {
    SignOutView(paramsFromRouter: ParamsFromRouter(url: URL(string: "/sign-out")!, path: "/", template: "/", params: [:]))
}
