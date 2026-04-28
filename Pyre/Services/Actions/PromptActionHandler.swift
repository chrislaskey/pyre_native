#if os(macOS)
import Foundation

/// Handles "prompt" actions by delegating the LLM call to NativeLLMBackend.
///
/// The server sends pre-built messages (system prompt with persona,
/// user message with artifacts/context). This handler routes to the
/// configured backend, streams output back, and returns the result text.
///
/// Mirrors PyreClient.Actions.Prompt — same payload, same result shape.
struct PromptActionHandler: NativeActionHandler {

    func execute(
        executionId: String,
        payload: [String: Any],
        channel: PhoenixChannelLiveView,
        runner: NativeRunner
    ) async {
        let messages = payload["messages"] as? [[String: Any]] ?? []
        let opts = payload["opts"] as? [String: Any] ?? [:]
        let backend = payload["backend"] as? String ?? "claude_cli"
        let interactive = (payload["interactive"] as? Bool) ?? false
        let modelTier = payload["model_tier"] as? String ?? "standard"
        let sessionId = opts["session_id"] as? String
        let workingDir = payload["working_dir"] as? String
        let maxTurns = opts["max_turns"] as? Int ?? 500

        let outputHandler: NativeLLMBackend.OutputHandler = { text in
            await MainActor.run {
                channel.pushAsync("action_output", [
                    "execution_id": executionId,
                    "content": text
                ])
            }
        }

        // Phase 1: LLM call
        let resultText: String
        do {
            resultText = try await NativeLLMBackend.call(
                backend: backend,
                modelTier: modelTier,
                messages: messages,
                sessionId: sessionId,
                maxTurns: maxTurns,
                workingDir: workingDir,
                onOutput: outputHandler
            )
        } catch {
            await sendError(
                executionId: executionId,
                reason: error.localizedDescription,
                channel: channel,
                runner: runner
            )
            return
        }

        // Phase 2: Send result
        if interactive {
            await MainActor.run {
                channel.pushAsync("action_result", [
                    "execution_id": executionId,
                    "result_text": resultText
                ])
            }

            await interactiveLoop(
                executionId: executionId,
                backend: backend,
                modelTier: modelTier,
                sessionId: sessionId,
                workingDir: workingDir,
                maxTurns: maxTurns,
                channel: channel,
                runner: runner,
                lastText: resultText
            )
        } else {
            await MainActor.run {
                channel.pushAsync("action_complete", [
                    "execution_id": executionId,
                    "status": "ok",
                    "result": ["text": resultText]
                ])
                runner.executionComplete(executionId: executionId, channel: channel)
            }
        }
    }

    // MARK: - Interactive Loop

    /// Blocks until action_finish, resuming the session on action_continue.
    /// Mirrors pyre_client's Runner.interactive_loop/3.
    private func interactiveLoop(
        executionId: String,
        backend: String,
        modelTier: String,
        sessionId: String?,
        workingDir: String?,
        maxTurns: Int,
        channel: PhoenixChannelLiveView,
        runner: NativeRunner,
        lastText: String
    ) async {
        var currentLastText = lastText

        let outputHandler: NativeLLMBackend.OutputHandler = { text in
            await MainActor.run {
                channel.pushAsync("action_output", [
                    "execution_id": executionId,
                    "content": text
                ])
            }
        }

        while true {
            let signal = await waitForSignal(runner: runner)

            switch signal {
            case .continueWith(let payload):
                let userMessage = payload["message"] as? String ?? ""

                do {
                    let text = try await NativeLLMBackend.resume(
                        backend: backend,
                        modelTier: modelTier,
                        userMessage: userMessage,
                        sessionId: sessionId,
                        maxTurns: maxTurns,
                        workingDir: workingDir,
                        onOutput: outputHandler
                    )
                    currentLastText = text.isEmpty ? currentLastText : text
                } catch {
                    await sendError(
                        executionId: executionId,
                        reason: "Resume error: \(error.localizedDescription)",
                        channel: channel,
                        runner: runner
                    )
                    return
                }

                await MainActor.run {
                    channel.pushAsync("action_result", [
                        "execution_id": executionId,
                        "result_text": currentLastText
                    ])
                }

            case .finish:
                await MainActor.run {
                    channel.pushAsync("action_complete", [
                        "execution_id": executionId,
                        "status": "ok",
                        "result": ["text": currentLastText]
                    ])
                    runner.executionComplete(executionId: executionId, channel: channel)
                }
                return
            }
        }
    }

    // MARK: - Signal Handling

    private enum InteractiveSignal {
        case continueWith(payload: [String: Any])
        case finish
    }

    /// Suspends until the server sends action_continue or action_finish.
    /// Uses NativeRunner's continuation/finish handler closures.
    private func waitForSignal(runner: NativeRunner) async -> InteractiveSignal {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                var hasResumed = false
                runner.activeExecution?.continuationHandler = { payload in
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: .continueWith(payload: payload))
                }
                runner.activeExecution?.finishHandler = {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: .finish)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sendError(
        executionId: String,
        reason: String,
        channel: PhoenixChannelLiveView,
        runner: NativeRunner
    ) async {
        await MainActor.run {
            channel.pushAsync("action_complete", [
                "execution_id": executionId,
                "status": "error",
                "result": ["error": reason]
            ])
            runner.executionComplete(executionId: executionId, channel: channel)
        }
    }
}
#endif
