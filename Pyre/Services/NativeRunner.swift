import Foundation
import Combine

/// Supporting type for tracking an active action execution.
struct ActiveExecution {
    let id: String
    let actionType: String
    let interactive: Bool
    let channel: PhoenixChannelLiveView
    var continuationHandler: (([String: Any]) -> Void)?
    var finishHandler: (() -> Void)?
}

/// Routes dispatched actions to handler modules, tracks capacity, and
/// manages the interactive loop. Mirrors PyreClient.Runner's role.
@MainActor
final class NativeRunner: ObservableObject {
    static let shared = NativeRunner()

    @Published private(set) var activeExecution: ActiveExecution?
    @Published private(set) var isRunning = false

    private let maxCapacity = 1

    var availableCapacity: Int {
        isRunning ? 0 : maxCapacity
    }

    var supportedBackends: [String] {
        #if os(macOS)
        // Advertises same backend names as pyre_client.
        // The server routes actions to workers with matching backends.
        return ["claude_cli", "cursor_cli", "claude_tmux"]
        #else
        return []  // iOS: no LLM execution yet
        #endif
    }

    // MARK: - Action Dispatch

    func dispatch(
        executionId: String,
        actionType: String,
        payload: [String: Any],
        channel: PhoenixChannelLiveView
    ) {
        guard !isRunning else {
            DebugLogger.warning("NativeRunner at capacity, rejecting \(executionId)")
            channel.pushAsync("action_complete", [
                "execution_id": executionId,
                "status": "error",
                "result": ["error": "Worker at capacity"]
            ])
            return
        }

        guard let handler = resolveHandler(actionType) else {
            DebugLogger.warning("Unsupported action type: \(actionType)")
            channel.pushAsync("action_complete", [
                "execution_id": executionId,
                "status": "error",
                "result": ["error": "Unsupported action type: \(actionType)"]
            ])
            return
        }

        isRunning = true
        let interactive = (payload["interactive"] as? Bool) ?? false
        activeExecution = ActiveExecution(
            id: executionId,
            actionType: actionType,
            interactive: interactive,
            channel: channel
        )

        updateCapacity(channel: channel)

        Task {
            await handler.execute(
                executionId: executionId,
                payload: payload,
                channel: channel,
                runner: self
            )
        }
    }

    // MARK: - Interactive Loop

    func handleContinue(executionId: String, payload: [String: Any]) {
        guard let execution = activeExecution, execution.id == executionId else {
            DebugLogger.warning("action_continue for unknown execution: \(executionId)")
            return
        }
        execution.continuationHandler?(payload)
    }

    func handleFinish(executionId: String) {
        guard let execution = activeExecution, execution.id == executionId else {
            DebugLogger.warning("action_finish for unknown execution: \(executionId)")
            return
        }
        execution.finishHandler?()
    }

    // MARK: - Completion

    func executionComplete(executionId: String, channel: PhoenixChannelLiveView) {
        guard activeExecution?.id == executionId else { return }
        activeExecution = nil
        isRunning = false
        updateCapacity(channel: channel)
    }

    // MARK: - Routing

    /// Routes action types to handler modules.
    /// Same action types as pyre_client — both workers are peers.
    private func resolveHandler(_ actionType: String) -> NativeActionHandler? {
        #if os(macOS)
        switch actionType {
        case "prompt":           return PromptActionHandler()
        case "git_pr_setup":     return GitPRSetupActionHandler()
        case "git_ship":         return GitShipActionHandler()
        case "git_review":       return GitReviewActionHandler()
        case "test_connection":  return TestConnectionHandler()
        case "reserve":          return ReserveHandler()
        default:                 return nil
        }
        #else
        return nil  // iOS: no action execution yet
        #endif
    }

    private func updateCapacity(channel: PhoenixChannelLiveView) {
        channel.pushAsync("update_metadata", [
            "available_capacity": availableCapacity
        ])
    }
}
