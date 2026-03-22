import SwiftUI
import Foundation
import Combine
import WebKit

// MARK: - SignInViewModel

class SignInViewModel: ObservableObject, PageViewModel {
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
}

// MARK: - SignInWebView

#if os(macOS)
struct SignInWebView: NSViewRepresentable {
    let url: URL
    var onSignInComplete: ((_ accessCookie: String?, _ refreshCookie: String?) -> Void)?

    func makeCoordinator() -> SignInWebViewCoordinator {
        SignInWebViewCoordinator(remoteURL: url, onSignInComplete: onSignInComplete)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct SignInWebView: UIViewRepresentable {
    let url: URL
    var onSignInComplete: ((_ accessCookie: String?, _ refreshCookie: String?) -> Void)?

    func makeCoordinator() -> SignInWebViewCoordinator {
        SignInWebViewCoordinator(remoteURL: url, onSignInComplete: onSignInComplete)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

class SignInWebViewCoordinator: NSObject, WKNavigationDelegate {
    let remoteURL: URL
    var onSignInComplete: ((_ accessCookie: String?, _ refreshCookie: String?) -> Void)?
    private var hasCompleted = false

    init(remoteURL: URL, onSignInComplete: ((_ accessCookie: String?, _ refreshCookie: String?) -> Void)?) {
        self.remoteURL = remoteURL
        self.onSignInComplete = onSignInComplete
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasCompleted else { return }
        guard webView.url?.path != remoteURL.path else { return }

        Task { @MainActor in
            guard !hasCompleted else { return }

            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

            let rememberMe = cookies.first { $0.name.hasSuffix("_remember_me") }
            let key = cookies.first { $0.name.hasSuffix("_key") }

            if rememberMe != nil || key != nil {
                DebugLogger.info("Sign-in cookies found: access=\(key != nil), refresh=\(rememberMe != nil)")
                hasCompleted = true
                onSignInComplete?(key?.value, rememberMe?.value)
            }
        }
    }
}

// MARK: - SignInView

struct SignInView: View {
    @EnvironmentObject var router: URLRouter

    @StateObject private var viewModel = SignInViewModel()
    @State private var paramsFromRouter: ParamsFromRouter
    @State private var handledFirstOnAppear = false

    private let remoteURL = URL(string: "http://localhost:4000/users/log-in")!

    init(paramsFromRouter: ParamsFromRouter) {
        self.paramsFromRouter = paramsFromRouter
    }

    var body: some View {
        SignInWebView(url: remoteURL) { accessCookie, refreshCookie in
            if let accessCookie {
                PyreWebAuth.upsert(type: .accessCookie, value: accessCookie)
            }
            if let refreshCookie {
                PyreWebAuth.upsert(type: .refreshCookie, value: refreshCookie)
            }
            router.navigate(to: RouterHelpers.getHomePath())
        }
        .withPageReloadable(viewModel: viewModel)
        .onAppear {
            if !handledFirstOnAppear {
                viewModel.mount(paramsFromRouter, router)
                handledFirstOnAppear = true
            }
        }
        .onDisappear {
            handledFirstOnAppear = false
        }
    }
}

#Preview {
    SignInView(paramsFromRouter: ParamsFromRouter(url: URL(string: "/sign-in")!, path: "/", template: "/", params: [:]))
}
