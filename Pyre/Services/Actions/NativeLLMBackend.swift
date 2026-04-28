#if os(macOS)
import Foundation

// MARK: - Errors

enum LLMBackendError: LocalizedError {
    case cliExitedNonZero
    case sessionWarmupFailed(String)
    case tmuxError(String)

    var errorDescription: String? {
        switch self {
        case .cliExitedNonZero:
            return "CLI exited with non-zero status"
        case .sessionWarmupFailed(let reason):
            return "Session warmup failed: \(reason)"
        case .tmuxError(let reason):
            return "Tmux error: \(reason)"
        }
    }
}

// MARK: - Backend Router

/// Routes LLM calls to the appropriate backend based on payload configuration.
/// Each handler delegates Phase 1 (the LLM call) through this router,
/// keeping backend selection out of action-specific logic.
enum NativeLLMBackend {

    typealias OutputHandler = (String) async -> Void

    /// Initial LLM call. Returns final result text.
    /// Streams text deltas to `onOutput` as they arrive.
    static func call(
        backend: String,
        modelTier: String,
        messages: [[String: Any]],
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        switch backend {
        case "cursor_cli":
            return try await callCursorCLI(
                modelTier: modelTier, messages: messages, sessionId: sessionId,
                maxTurns: maxTurns, workingDir: workingDir, onOutput: onOutput
            )
        case "claude_tmux":
            return try await callClaudeTmux(
                modelTier: modelTier, messages: messages, sessionId: sessionId,
                maxTurns: maxTurns, workingDir: workingDir, onOutput: onOutput
            )
        default:
            return try await callClaudeCLI(
                modelTier: modelTier, messages: messages, sessionId: sessionId,
                maxTurns: maxTurns, workingDir: workingDir, onOutput: onOutput
            )
        }
    }

    /// Resume an existing session. Returns final result text.
    static func resume(
        backend: String,
        modelTier: String,
        userMessage: String,
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        switch backend {
        case "cursor_cli":
            return try await resumeCursorCLI(
                modelTier: modelTier, userMessage: userMessage, sessionId: sessionId,
                maxTurns: maxTurns, workingDir: workingDir, onOutput: onOutput
            )
        case "claude_tmux":
            return try await resumeClaudeTmux(
                modelTier: modelTier, userMessage: userMessage, sessionId: sessionId,
                workingDir: workingDir, onOutput: onOutput
            )
        default:
            return try await resumeClaudeCLI(
                modelTier: modelTier, userMessage: userMessage, sessionId: sessionId,
                maxTurns: maxTurns, workingDir: workingDir, onOutput: onOutput
            )
        }
    }

    // MARK: - Claude CLI

    private static func callClaudeCLI(
        modelTier: String,
        messages: [[String: Any]],
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        let model = ClaudeCLIHelper.mapModelTier(modelTier)
        let (systemPrompt, userPrompt) = ClaudeCLIHelper.extractPrompts(messages)

        let fullPrompt = sessionId != nil
            ? userPrompt + "\n\n" + ClaudeCLIHelper.nonInteractiveNote
            : userPrompt

        let command = ClaudeCLIHelper.buildChatCommand(
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: fullPrompt,
            sessionId: sessionId,
            maxTurns: maxTurns,
            workingDir: workingDir
        )

        return try await runStreamingCLI(command, onOutput: onOutput)
    }

    private static func resumeClaudeCLI(
        modelTier: String,
        userMessage: String,
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        let model = ClaudeCLIHelper.mapModelTier(modelTier)

        let command = ClaudeCLIHelper.buildChatCommand(
            model: model,
            systemPrompt: "",
            userPrompt: userMessage,
            sessionId: sessionId,
            resume: true,
            maxTurns: maxTurns,
            workingDir: workingDir
        )

        return try await runStreamingCLI(command, onOutput: onOutput)
    }

    // MARK: - Cursor CLI

    private static func callCursorCLI(
        modelTier: String,
        messages: [[String: Any]],
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        let model = CursorCLIHelper.mapModelTier(modelTier)
        let (_, userPrompt) = CursorCLIHelper.extractPrompts(messages)

        if let pyreSessionId = sessionId {
            // Session warm-up strategy: ensure cursor session, then resume with real prompt
            let cursorId = try await CursorCLIHelper.ensureSession(
                pyreSessionId: pyreSessionId,
                model: model,
                systemPrompt: ClaudeCLIHelper.extractPrompts(messages).system,
                workingDir: workingDir
            )

            let prompt = CursorCLIHelper.extractUserParts(messages)
                + "\n\n" + CursorCLIHelper.nonInteractiveNote

            let command = CursorCLIHelper.buildResumeCommand(
                model: model,
                cursorSessionId: cursorId,
                userPrompt: prompt,
                workingDir: workingDir
            )

            return try await runStreamingCLI(command, onOutput: onOutput)
        } else {
            let fullPrompt = userPrompt + "\n\n" + CursorCLIHelper.nonInteractiveNote

            let command = CursorCLIHelper.buildStatelessCommand(
                model: model,
                userPrompt: fullPrompt,
                workingDir: workingDir
            )

            return try await runStreamingCLI(command, onOutput: onOutput)
        }
    }

    private static func resumeCursorCLI(
        modelTier: String,
        userMessage: String,
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        let model = CursorCLIHelper.mapModelTier(modelTier)

        if let pyreSessionId = sessionId,
           let cursorId = await CursorSessionRegistry.shared.get(pyreSessionId) {
            let command = CursorCLIHelper.buildResumeCommand(
                model: model,
                cursorSessionId: cursorId,
                userPrompt: userMessage,
                workingDir: workingDir
            )
            return try await runStreamingCLI(command, onOutput: onOutput)
        } else {
            // No session mapping — run stateless
            let command = CursorCLIHelper.buildStatelessCommand(
                model: model,
                userPrompt: userMessage,
                workingDir: workingDir
            )
            return try await runStreamingCLI(command, onOutput: onOutput)
        }
    }

    // MARK: - Claude Tmux

    private static func callClaudeTmux(
        modelTier: String,
        messages: [[String: Any]],
        sessionId: String?,
        maxTurns: Int,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        guard let sessionId = sessionId else {
            // No session — fall back to Claude CLI for stateless calls
            // (mirrors Elixir ClaudeTmux which delegates to ClaudeCLI for non-session calls)
            return try await callClaudeCLI(
                modelTier: modelTier, messages: messages, sessionId: nil,
                maxTurns: maxTurns, workingDir: workingDir, onOutput: onOutput
            )
        }

        let model = ClaudeCLIHelper.mapModelTier(modelTier)
        let (systemPrompt, userPrompt) = ClaudeCLIHelper.extractPrompts(messages)
        let prompt = userPrompt + "\n\n" + ClaudeTmuxHelper.interactionNote

        let text = try await ClaudeTmuxHelper.runChat(
            sessionId: sessionId,
            model: model,
            systemPrompt: systemPrompt,
            prompt: prompt,
            workingDir: workingDir
        )

        if !text.isEmpty {
            await onOutput(text)
        }

        return text
    }

    private static func resumeClaudeTmux(
        modelTier: String,
        userMessage: String,
        sessionId: String?,
        workingDir: String?,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        guard let sessionId = sessionId else {
            throw LLMBackendError.tmuxError("Cannot resume tmux session without session ID")
        }

        // On resume, send just the user message (no persona wrapping)
        let text = try await ClaudeTmuxHelper.runChat(
            sessionId: sessionId,
            model: "",  // Claude is already running; model is ignored
            systemPrompt: "",
            prompt: userMessage,
            workingDir: workingDir,
            skipClaudeStartup: true  // Claude is already running from initial call
        )

        if !text.isEmpty {
            await onOutput(text)
        }

        return text
    }

    // MARK: - Shared Streaming Helper

    /// Runs a CLI command with NDJSON streaming, accumulating text and result.
    /// Used by both Claude CLI and Cursor CLI backends.
    private static func runStreamingCLI(
        _ command: String,
        onOutput: @escaping OutputHandler
    ) async throws -> String {
        let acc = StreamAccumulator()

        let status = try await ShellExecutor.stream(command, onStart: { _ in }) { line in
            if let text = ClaudeCLIHelper.extractTextDelta(line) {
                acc.text += text
                await onOutput(text)
            }
            if let result = ClaudeCLIHelper.parseResultLine(line) {
                acc.finalResult = result
            }
        }

        guard status.isSuccess else {
            throw LLMBackendError.cliExitedNonZero
        }

        return acc.resultText
    }
}
#endif
