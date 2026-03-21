import Foundation

/// Base protocol for all page ViewModels.
///
/// ## Lifecycle:
/// 1. `init` - ViewModel is created (when View is created)
/// 2. `fetchParams(_:)` - Called in onAppear, sets up params and connects to backend
/// 3. `handleParams(_:)` - Called after channel successfully joins with response payload
/// 4. `deinit` - Automatic cleanup when ViewModel is destroyed
///
/// ## Data Flow:
/// ```
/// View.onAppear → fetchParams(paramsFromRouter) → connect() → handleParams(payload)
/// ```
///
protocol PageViewModel: ObservableObject {
    /// Entrypoint for the viewModel. Called the first time the view calls
    /// `onAppear`. Subsequent `onAppear` calls do not call `mount` again.
    ///
    /// - Parameter paramsFromRouter: The path and extracted route parameters
    /// - Parameter router: The router instance
    func mount(_ paramsFromRouter: ParamsFromRouter, _ router: URLRouter)

    /// Reload the page. Required by the `View+Refreshable` extension.
    func reload()
    
    /// Handle loaded page params.
    /// Called after data fetching is complete.
    ///
    /// - Parameter payload: The channel join response payload
    func handleParams(_ payload: [String: Any])
}
