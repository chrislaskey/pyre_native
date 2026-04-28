#if os(macOS)
import Foundation

/// Thread-safe accumulator for streaming CLI output.
/// Safe because ShellExecutor.stream calls onLine sequentially.
final class StreamAccumulator: @unchecked Sendable {
    var text = ""
    var finalResult: String? = nil

    var resultText: String { finalResult ?? text }
}

/// Shared utilities for building and parsing Claude CLI invocations.
/// Mirrors pyre_client's PyreClient.LLM.ClaudeCLI module.
enum ClaudeCLIHelper {

    static let nonInteractiveNote = """
    Note: This is a non-interactive session running inside an automated \
    pipeline. If you have questions or need clarification before proceeding, \
    include them clearly at the end of your response — the user can reply by \
    resuming this session.
    """

    // MARK: - Model Mapping

    /// Maps server model_tier values to Claude CLI model names.
    static func mapModelTier(_ tier: String) -> String {
        switch tier {
        case "fast":     return "haiku"
        case "standard": return "sonnet"
        case "advanced": return "opus"
        default:         return tier
        }
    }

    // MARK: - Prompt Extraction

    /// Extracts system and user prompts from the server's messages array.
    /// Embeds the system prompt in the user prompt inside <persona> tags
    /// for more reliable persona adherence (matches Elixir ClaudeCLI behavior).
    static func extractPrompts(_ messages: [[String: Any]]) -> (system: String, user: String) {
        let systemParts = messages
            .filter { ($0["role"] as? String) == "system" }
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n\n")

        let userParts = messages
            .filter { ($0["role"] as? String) == "user" }
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n\n")

        let userPrompt: String
        if !systemParts.isEmpty {
            userPrompt = """
            <persona>
            \(systemParts)
            </persona>

            You MUST follow the persona instructions above for the duration of this task. \
            Stay in character, use the output format specified, and do not deviate from the role described.

            \(userParts)
            """
        } else {
            userPrompt = userParts
        }

        return (system: systemParts, user: userPrompt)
    }

    // MARK: - Command Building

    /// Builds a complete Claude CLI command string for shell execution.
    ///
    /// - Parameters:
    ///   - model: CLI model name (e.g., "sonnet", "haiku", "opus")
    ///   - systemPrompt: System prompt for --append-system-prompt (empty string skips it)
    ///   - userPrompt: User prompt passed via -p flag
    ///   - sessionId: Session ID for --session-id or --resume
    ///   - resume: If true, uses --resume instead of --session-id
    ///   - maxTurns: Maximum agentic turns (default 500)
    ///   - workingDir: Working directory (prepends cd command if set)
    static func buildChatCommand(
        model: String,
        systemPrompt: String,
        userPrompt: String,
        sessionId: String?,
        resume: Bool = false,
        maxTurns: Int = 500,
        workingDir: String?
    ) -> String {
        var parts: [String] = []

        if let dir = workingDir {
            parts.append("cd \(shellEscape(dir)) &&")
        }

        parts.append("claude")
        parts.append("--model \(shellEscape(model))")

        if !systemPrompt.isEmpty {
            parts.append("--append-system-prompt \(shellEscape(systemPrompt))")
        }

        parts.append("--permission-mode bypassPermissions")
        parts.append("--allowedTools 'Bash,Read,Edit,Write,Glob,Grep'")

        if resume, let sid = sessionId {
            parts.append("--resume \(shellEscape(sid))")
        } else if let sid = sessionId {
            parts.append("--session-id \(shellEscape(sid))")
        } else {
            parts.append("--no-session-persistence")
        }

        parts.append("--max-turns \(maxTurns)")
        parts.append("--output-format stream-json")
        parts.append("--verbose")
        parts.append("-p \(shellEscape(userPrompt))")
        parts.append("</dev/null")

        return parts.joined(separator: " ")
    }

    // MARK: - Stream-JSON Parsing

    /// Extracts text content from a stream-json NDJSON line.
    /// Handles: stream_event wrappers, bare content_block_delta, assistant messages.
    /// Returns nil if the line doesn't contain displayable text.
    static func extractTextDelta(_ jsonLine: String) -> String? {
        guard let data = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            return nil
        }

        switch eventType {
        case "stream_event":
            if let event = json["event"] as? [String: Any] {
                return extractDeltaText(event)
            }

        case "content_block_delta":
            return extractDeltaText(json)

        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                let text = content
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()
                return text.isEmpty ? nil : text
            }

        default:
            break
        }

        return nil
    }

    /// Extracts the final result text from a stream-json "result" event.
    /// Returns nil if the line isn't a result event.
    static func parseResultLine(_ jsonLine: String) -> String? {
        guard let data = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String, eventType == "result",
              let result = json["result"] as? String else {
            return nil
        }
        return result
    }

    // MARK: - Shell Escaping

    /// Wraps a string in single quotes for safe shell interpolation.
    static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Private

    private static func extractDeltaText(_ event: [String: Any]) -> String? {
        guard let eventType = event["type"] as? String, eventType == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String, deltaType == "text_delta",
              let text = delta["text"] as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
}
#endif
