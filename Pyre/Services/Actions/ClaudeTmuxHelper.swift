#if os(macOS)
import Foundation

/// Shared utilities for tmux-wrapped Claude sessions.
/// Mirrors pyre_custom's App.Pyre.Config.Custom.LLM.ClaudeTmux module.
///
/// Key difference from ClaudeCLI/CursorCLI: instead of subprocess streaming,
/// this backend manages a persistent Claude process inside a tmux session,
/// sends prompts via `tmux send-keys`, and reads responses from scrollback.
enum ClaudeTmuxHelper {

    static let interactionNote = """
    Note: Do NOT use interactive questions since they display incorrectly \
    sometimes. If you have questions or need clarification before proceeding, \
    include them clearly at the end of your response instead of — the user \
    will reply in their next prompt.
    """

    private static let settlePollMs: UInt64 = 350
    private static let settleRequiredStableReads = 3
    private static let claudeStartupWaitMs: UInt64 = 250
    private static let claudeReadyTimeoutMs: UInt64 = 250
    private static let promptEnterDelayMs: UInt64 = 1_000
    private static let defaultTimeoutMs: UInt64 = 600_000

    // MARK: - High-Level Chat

    /// Runs a full chat turn: ensure tmux session, ensure Claude is running,
    /// capture scrollback, send prompt, wait for settle, extract delta.
    ///
    /// - Parameter skipClaudeStartup: If true, skips checking/starting Claude
    ///   (used on resume where Claude is already running).
    static func runChat(
        sessionId: String,
        model: String,
        systemPrompt: String,
        prompt: String,
        workingDir: String?,
        skipClaudeStartup: Bool = false,
        timeoutMs: UInt64 = 600_000
    ) async throws -> String {
        try await ensureTmuxSession(sessionId: sessionId, workingDir: workingDir)

        if !skipClaudeStartup {
            try await ensureClaudeRunning(
                sessionId: sessionId,
                model: model,
                systemPrompt: systemPrompt
            )
        }

        let before = try await captureScrollback(sessionId: sessionId)
        try await writePrompt(sessionId: sessionId, prompt: prompt)
        let after = try await waitForScrollbackSettle(
            sessionId: sessionId,
            baseline: before,
            timeoutMs: timeoutMs
        )

        return extractDelta(before: before, after: after)
    }

    // MARK: - Tmux Session Management

    static func ensureTmuxSession(sessionId: String, workingDir: String?) async throws {
        let (_, hasSuccess) = await runTmux(["has-session", "-t", sessionId])
        if hasSuccess { return }

        var args = ["new-session", "-d", "-s", sessionId]
        if let dir = workingDir {
            args += ["-c", dir]
        }

        let (output, success) = await runTmux(args)
        guard success else {
            throw LLMBackendError.tmuxError("Failed to create tmux session: \(output)")
        }
    }

    // MARK: - Claude Process Management

    static func ensureClaudeRunning(
        sessionId: String,
        model: String,
        systemPrompt: String
    ) async throws {
        let paneCmd = try await paneCurrentCommand(sessionId: sessionId)

        if isClaudeRunning(paneCmd) {
            return
        }

        let startCmd = buildClaudeStartCommand(model: model, systemPrompt: systemPrompt)

        try await sendKeysLiteral(sessionId: sessionId, text: startCmd)
        try await sendEnter(sessionId: sessionId)

        try await Task.sleep(nanoseconds: claudeStartupWaitMs * 1_000_000)
        try await waitForClaudeReady(sessionId: sessionId, timeoutMs: claudeReadyTimeoutMs)
    }

    private static func buildClaudeStartCommand(model: String, systemPrompt: String) -> String {
        var args = [
            "claude",
            "--model", model,
            "--permission-mode", "bypassPermissions",
            "--allowedTools", "Bash,Read,Edit,Write,Glob,Grep"
        ]

        if !systemPrompt.isEmpty {
            args += ["--append-system-prompt", systemPrompt]
        }

        return args.map { shellEscape($0) }.joined(separator: " ")
    }

    private static func paneCurrentCommand(sessionId: String) async throws -> String {
        let (output, success) = await runTmux(
            ["list-panes", "-t", sessionId, "-F", "#{pane_current_command}"]
        )
        guard success else {
            throw LLMBackendError.tmuxError("Failed to get pane command")
        }

        let lines = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard let first = lines.first, !first.isEmpty else {
            throw LLMBackendError.tmuxError("No pane found in session")
        }
        return first
    }

    private static func isClaudeRunning(_ paneCmd: String) -> Bool {
        let normalized = paneCmd.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "claude"
    }

    private static func waitForClaudeReady(sessionId: String, timeoutMs: UInt64) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + (timeoutMs * 1_000_000)

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let cmd = try? await paneCurrentCommand(sessionId: sessionId),
               cmd.lowercased() == "claude" {
                return
            }
            try await Task.sleep(nanoseconds: 150 * 1_000_000)
        }
        // Timeout is non-fatal — continue anyway (matches Elixir behavior)
    }

    // MARK: - Prompt Writing

    static func writePrompt(sessionId: String, prompt: String) async throws {
        try await sendKeysLiteral(sessionId: sessionId, text: prompt)
        try await Task.sleep(nanoseconds: promptEnterDelayMs * 1_000_000)
        try await sendEnter(sessionId: sessionId)
    }

    private static func sendKeysLiteral(sessionId: String, text: String) async throws {
        // tmux send-keys -l passes text as-is (no key name interpretation).
        // Use Process directly (not shell strings) to avoid escaping issues
        // with arbitrarily complex prompt text.
        let (output, success) = await runTmux(["send-keys", "-t", sessionId, "-l", "--", text])
        guard success else {
            throw LLMBackendError.tmuxError("Failed to send keys: \(output)")
        }
    }

    private static func sendEnter(sessionId: String) async throws {
        let (output, success) = await runTmux(["send-keys", "-t", sessionId, "C-m"])
        guard success else {
            throw LLMBackendError.tmuxError("Failed to send Enter: \(output)")
        }
    }

    // MARK: - Scrollback Capture & Settle

    static func captureScrollback(sessionId: String) async throws -> String {
        let (output, success) = await runTmux(
            ["capture-pane", "-p", "-S", "-", "-t", sessionId]
        )
        guard success else {
            throw LLMBackendError.tmuxError("Failed to capture scrollback")
        }
        return output
    }

    static func waitForScrollbackSettle(
        sessionId: String,
        baseline: String,
        timeoutMs: UInt64
    ) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + (timeoutMs * 1_000_000)
        var previousCapture = ""
        var stableCount = 0

        while DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(nanoseconds: settlePollMs * 1_000_000)

            let capture = try await captureScrollback(sessionId: sessionId)

            if capture == previousCapture {
                stableCount += 1
            } else {
                stableCount = 0
            }

            let delta = extractDelta(before: baseline, after: capture)

            if stableCount >= settleRequiredStableReads
                && !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return capture
            }

            previousCapture = capture
        }

        // Timeout — return whatever we have
        return previousCapture
    }

    // MARK: - Delta Extraction

    static func extractDelta(before: String, after: String) -> String {
        if after.hasPrefix(before) {
            return String(after.dropFirst(before.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return after.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tmux Subprocess

    /// Runs a tmux command using Process directly (bypasses shell interpretation).
    /// This avoids escaping issues when passing complex text through tmux send-keys.
    private static func runTmux(_ args: [String]) async -> (output: String, isSuccess: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let outPipe = Pipe()

                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["tmux"] + args
                    process.standardOutput = outPipe
                    process.standardError = outPipe

                    try process.run()

                    // Read all data before waitUntilExit to avoid pipe buffer deadlock
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(
                        returning: (output: output, isSuccess: process.terminationStatus == 0)
                    )
                } catch {
                    continuation.resume(
                        returning: (output: error.localizedDescription, isSuccess: false)
                    )
                }
            }
        }
    }

    // MARK: - Shell Escaping

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
