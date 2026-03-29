import SwiftUI

@main
struct PyreApp: App {
    @StateObject private var router = URLRouter()
    @StateObject private var connectionPresence = ConnectionPresenceService()
    #if os(macOS)
    @StateObject private var remoteCommands = RemoteCommandService.shared
    #endif
    @State private var showRouterOverlay = false

    init() {
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            ProcessTracker.shared.killAll()
            MainActor.assumeIsolated {
                PhoenixChannelService.shared.disconnectAll()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RouterView()
                .environmentObject(router)
                .environmentObject(connectionPresence)
                #if os(macOS)
                .environmentObject(remoteCommands)
                .fullBleedWindow()
                #endif
                .onOpenURL { url in
                    RouterHelpers.handleUniversalLink(url, router: router)
                }
                .sheet(isPresented: $showRouterOverlay) {
                    RouterOverlay(router: router)
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reload Page") {
                    router.reconnect()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Go to Route…") {
                    showRouterOverlay.toggle()
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
