#if os(macOS)
import Foundation

/// Handles "git_pr_setup" actions — LLM call via NativeLLMBackend,
/// parse shipping plan, git checkout/add/commit/push, create draft PR.
///
/// Error policy: fail on any git/github error (matches pyre_client).
/// Mirrors PyreClient.Actions.GitPRSetup — same payload, same result shape.
struct GitPRSetupActionHandler: NativeActionHandler {

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

        // Phase 2: Git operations — fail-fast pipeline
        guard let plan = GitHelper.parseShippingPlan(text) else {
            await sendError(executionId: executionId, reason: "Failed to parse shipping plan from LLM output", channel: channel, runner: runner)
            return
        }

        do {
            GitHelper.editGitignore(workingDir: workingDir)
            try await GitHelper.checkoutOrCreateBranch(plan.branchName, workingDir: workingDir)
            try await GitHelper.addAll(workingDir: workingDir)
            try await GitHelper.commit(message: plan.commitMessage, workingDir: workingDir)
            try await GitHelper.push(branch: plan.branchName, workingDir: workingDir)
        } catch {
            await sendError(executionId: executionId, reason: error.localizedDescription, channel: channel, runner: runner)
            return
        }

        // GitHub: create draft PR
        guard let config = githubConfig else {
            await sendError(executionId: executionId, reason: "Missing github config in payload", channel: channel, runner: runner)
            return
        }

        do {
            let pr = try await GitHubHelper.createPullRequest(config: config, plan: plan, draft: true)

            await MainActor.run {
                channel.pushAsync("action_complete", [
                    "execution_id": executionId,
                    "status": "ok",
                    "result": [
                        "text": text,
                        "branch_name": plan.branchName,
                        "pr_url": pr.url,
                        "pr_number": pr.number
                    ] as [String: Any]
                ])
                runner.executionComplete(executionId: executionId, channel: channel)
            }
        } catch {
            await sendError(executionId: executionId, reason: error.localizedDescription, channel: channel, runner: runner)
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
