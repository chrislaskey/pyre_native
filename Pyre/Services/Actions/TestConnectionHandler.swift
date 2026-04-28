import Foundation

/// Simple connection health check.
///
/// Unlike other handlers, TestConnectionHandler doesn't perform LLM calls.
/// It immediately responds with a timestamp to confirm the client received
/// the request and the round-trip communication is working.
///
/// Mirrors `PyreClient.Actions.TestConnection` + the `execute_test_connection/1`
/// clause in the Elixir runner.
struct TestConnectionHandler: NativeActionHandler {
    func execute(
        executionId: String,
        payload: [String: Any],
        channel: PhoenixChannelLiveView,
        runner: NativeRunner
    ) async {
        DebugLogger.log("[\(executionId)] test_connection — responding")

        let timestamp = ISO8601DateFormatter().string(from: Date())

        channel.pushAsync("action_complete", [
            "execution_id": executionId,
            "status": "ok",
            "result": ["message": "Received test connection request! Responded at \(timestamp)"]
        ])

        await runner.executionComplete(executionId: executionId, channel: channel)
    }
}
