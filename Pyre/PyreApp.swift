import SwiftUI

@main
struct PyreApp: App {
    @StateObject private var router = URLRouter()

    init() {
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            ProcessTracker.shared.killAll()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RouterView()
                .environmentObject(router)
                .onOpenURL { url in
                    RouterHelpers.handleUniversalLink(url, router: router)
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
