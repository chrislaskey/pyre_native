import SwiftUI

/// Helper view that redirects to a different route
struct RedirectView: View {
    let to: String
    let router: URLRouter
    let showErrorImmediately: Bool
    
    @State private var showLoopError = false
    @State private var redirectAttempted = false
    
    init(to: String, router: URLRouter, showErrorImmediately: Bool = false) {
        self.to = to
        self.router = router
        self.showErrorImmediately = showErrorImmediately
    }
    
    var body: some View {
        ZStack {
            Color.clear
            
            if showLoopError || showErrorImmediately {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Redirect Loop Detected")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Unable to navigate to:")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text(to)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    
                    ActionButton(
                        title: "Sign Out",
                        backgroundColor: .blue
                    ) {
                        router.navigate(to: "/sign-out")
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .padding()
            }
        }
        .onAppear {
            if !showErrorImmediately {
                handleRedirect()
            }
        }
    }
    
    private func handleRedirect() {
        let isRedirectLoop = router.currentURL.path == to

        if isRedirectLoop {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showLoopError = true
            }
        } else if !redirectAttempted {
            redirectAttempted = true
            router.navigate(to: to)
        }
    }
}
