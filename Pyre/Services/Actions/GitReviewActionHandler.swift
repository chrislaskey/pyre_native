#if os(macOS)
import Foundation

/// Handles "git_review" actions — LLM call via NativeLLMBackend,
/// parse verdict, fire-and-forget git + GitHub comment.
///
/// Error policy: git/GitHub are fire-and-forget; action succeeds if LLM succeeds.
/// Mirrors PyreClient.Actions.GitReview — same payload, same result shape.
struct GitReviewActionHandler: NativeActionHandler {

    func execute(
        executionId: String,
        payload: [String: Any],
        channel: PhoenixChannelLiveView,
        runner: NativeRunner
    ) async {
        let messages = payload["messages"] as? [[String: Any]] ?? []
        let opts = payload["opts"] as? [String: Any] ?? [:]
        let backend = payload["backend"] as? String ?? "claude_cli"
        let modelTier = payload["model_tier"] as? String ?? "standard"
        let sessionId = opts["session_id"] as? String
        let workingDir = payload["working_dir"] as? String ?? "."
        let maxTurns = opts["max_turns"] as? Int ?? 500
        let prNumber = payload["pr_number"]
        let githubConfig = payload["github"] as? [String: Any]

        let outputHandler: NativeLLMBackend.OutputHandler = { text in
            await MainActor.run {
                channel.pushAsync("action_output", [
                    "execution_id": executionId,
                    "content": text
                ])
            }
        }

        // Phase 1: LLM call
        let text: String
        do {
            text = try await NativeLLMBackend.call(
                backend: backend,
                modelTier: modelTier,
                messages: messages,
                sessionId: sessionId,
                maxTurns: maxTurns,
                workingDir: workingDir,
                onOutput: outputHandler
            )
        } catch {
            await sendError(executionId: executionId, reason: error.localizedDescription, channel: channel, runner: runner)
            return
        }

        let verdict = GitHelper.parseVerdict(text)

        // Phase 2: Git operations — fire and forget
        do {
            try await GitHelper.addAll(workingDir: workingDir)
            try await GitHelper.commit(message: "Code review changes", workingDir: workingDir)
            try await GitHelper.pushCurrentBranch(workingDir: workingDir)
        } catch {
            DebugLogger.warning("GitReview git ops failed (non-fatal): \(error.localizedDescription)")
        }

        // GitHub operations — fire and forget
        if let config = githubConfig, let prNum = prNumber {
            do {
                try await GitHubHelper.createComment(config: config, prNumber: prNum, body: text)

                if verdict == "approve" {
                    try await GitHubHelper.markReadyForReview(config: config, prNumber: prNum)
                }
            } catch {
                DebugLogger.warning("GitReview GitHub ops failed (non-fatal): \(error.localizedDescription)")
            }
        }

        // Action succeeds if LLM succeeded (regardless of git/github errors)
        await MainActor.run {
            channel.pushAsync("action_complete", [
                "execution_id": executionId,
                "status": "ok",
                "result": ["text": text, "verdict": verdict]
            ])
            runner.executionComplete(executionId: executionId, channel: channel)
        }
    }

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
