import Foundation

/// Protocol for action handler modules.
///
/// Each action type (`prompt`, `git_pr_setup`, `git_ship`, `git_review`) gets
/// a dedicated handler conforming to this protocol. Mirrors pyre_client's
/// `PyreClient.Actions.*` module pattern.
///
/// Handlers receive pre-built payloads from the server (messages, model tier,
/// role, etc.) and decide internally what to execute. The server never sends
/// arbitrary shell commands.
protocol NativeActionHandler {
    func execute(
        executionId: String,
        payload: [String: Any],
        channel: PhoenixChannelLiveView,
        runner: NativeRunner
    ) async
}
