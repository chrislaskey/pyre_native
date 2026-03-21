import SwiftUI

/// Extension to add automatic page reconnect and refresh functionality
/// Works with any ViewModel that conforms to PageViewModel protocol
extension View {
    /// Add automatic reconnect and refresh support for pages with PageViewModel
    ///
    /// This modifier automatically enables:
    /// - Command+R reconnect (via router.reloadTrigger observation)
    /// - Pull-to-refresh on iOS
    ///
    /// - Parameter viewModel: Any ViewModel that conforms to PageViewModel
    /// - Returns: A view with automatic reconnect capabilities
    ///
    /// Usage:
    /// ```swift
    /// struct MyPage: View {
    ///     @EnvironmentObject var router: URLRouter
    ///     @StateObject var viewModel: MyViewModel
    ///     
    ///     var body: some View {
    ///         ScrollView {
    ///             // content
    ///         }
    ///         .withPageReloadable(viewModel: viewModel)
    ///     }
    /// }
    /// ```
    func withPageReloadable<VM: PageViewModel>(viewModel: VM) -> some View {
        self.modifier(PageReloadableModifier(viewModel: viewModel))
    }
}

/// Internal modifier that wraps the view to observe router's reloadTrigger
private struct PageReloadableModifier<VM: PageViewModel>: ViewModifier {
    @EnvironmentObject var router: URLRouter
    let viewModel: VM
    
    func body(content: Content) -> some View {
        content
            // Pull-to-refresh (iOS)
            .refreshable {
                viewModel.reload()
                // Small delay to let reconnection complete
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            }
            // Command+R reconnect - observes router's reloadTrigger UUID
            .onChange(of: router.reloadTrigger) { _, _ in
                viewModel.reload()
            }
    }
}
