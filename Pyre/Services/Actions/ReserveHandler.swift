import Foundation

/// Capacity reservation for workflow execution.
///
/// Unlike other handlers, ReserveHandler doesn't perform LLM calls. It
/// immediately acknowledges the reservation, then holds the capacity slot
/// until the server sends `action_finish` when the workflow completes.
///
/// Mirrors `PyreClient.Actions.Reserve` + the `execute_reserve/1` clause
/// in the Elixir runner.
struct ReserveHandler: NativeActionHandler {
    func execute(
        executionId: String,
        payload: [String: Any],
        channel: PhoenixChannelLiveView,
        runner: NativeRunner
    ) async {
        DebugLogger.log("[\(executionId)] reserve — acking and holding capacity")

        // Acknowledge reservation immediately.
        // Matches Elixir: send_to_server("action_output", %{type: "ack", status: "accepted"})
        channel.pushAsync("action_output", [
            "execution_id": executionId,
            "type": "ack",
            "status": "accepted"
        ])

        // Block until the server sends action_finish when the workflow completes.
        // This keeps the execution active, holding the capacity slot.
        // Mirrors Elixir's `receive do :finish -> ...` in execute_reserve/1.
        await waitForFinish(runner: runner)

        DebugLogger.log("[\(executionId)] reserve — released")

        await MainActor.run {
            runner.executionComplete(executionId: executionId, channel: channel)
        }
    }

    /// Suspends until the server sends `action_finish`.
    /// Uses NativeRunner's finish handler closure — same pattern as
    /// PromptActionHandler's `waitForSignal`, but only listens for finish.
    private func waitForFinish(runner: NativeRunner) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                runner.activeExecution?.finishHandler = {
                    continuation.resume()
                }
            }
        }
    }
}
