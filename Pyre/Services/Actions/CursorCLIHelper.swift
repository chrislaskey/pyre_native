#if os(macOS)
import Foundation

// MARK: - Session Registry

/// Maps Pyre session IDs to Cursor-generated session IDs.
/// Cursor cannot accept a pre-specified session ID on first call,
/// so we warm up, extract the cursor ID, and store the mapping.
actor CursorSessionRegistry {
    static let shared = CursorSessionRegistry()
    private var mapping: [String: String] = [:]

    func get(_ pyreId: String) -> String? { mapping[pyreId] }
    func put(_ pyreId: String, cursorId: String) { mapping[pyreId] = cursorId }
}

// MARK: - Cursor CLI Helper

/// Shared utilities for cursor-agent CLI invocations.
/// Mirrors pyre_client's PyreClient.LLM.CursorCLI module.
enum CursorCLIHelper {

    static let nonInteractiveNote = """
    Note: This is a non-interactive session running inside an automated \
    pipeline. If you have questions or need clarification before \
    proceeding, include them clearly at the end of your response — \
    the user can reply by resuming this session.
    """

    // MARK: - Model Mapping

    /// Maps server model_tier values to cursor-agent model names.
    /// Cursor uses full model identifiers (not short aliases like Claude CLI).
    static func mapModelTier(_ tier: String) -> String {
        switch tier {
        case "fast":     return "claude-haiku-4-5"
        case "standard": return "claude-sonnet-4-5"
        case "advanced": return "claude-opus-4"
        default:         return tier
        }
    }

    // MARK: - Prompt Extraction

    /// Reuses ClaudeCLIHelper's prompt extraction (same <persona> tag pattern).
    static func extractPrompts(_ messages: [[String: Any]]) -> (system: String, user: String) {
        ClaudeCLIHelper.extractPrompts(messages)
    }

    /// Extracts only user-role content from messages (no persona wrapping).
    /// Used for session resume calls where persona is already established.
    static func extractUserParts(_ messages: [[String: Any]]) -> String {
        messages
            .filter { ($0["role"] as? String) == "user" }
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n\n")
    }

    // MARK: - Command Building

    /// Builds a stateless cursor-agent command (no session).
    static func buildStatelessCommand(
        model: String,
        userPrompt: String,
        workingDir: String?
    ) -> String {
        var parts: [String] = []

        if let dir = workingDir {
            parts.append("cd \(shellEscape(dir)) &&")
        }

        parts.append("cursor-agent")
        parts.append("--model \(shellEscape(model))")
        parts.append("--yolo")
        parts.append("--output-format stream-json")
        parts.append("-p \(shellEscape(userPrompt))")
        parts.append("</dev/null")

        return parts.joined(separator: " ")
    }

    /// Builds a cursor-agent resume command for an existing session.
    static func buildResumeCommand(
        model: String,
        cursorSessionId: String,
        userPrompt: String,
        workingDir: String?
    ) -> String {
        var parts: [String] = []

        if let dir = workingDir {
            parts.append("cd \(shellEscape(dir)) &&")
        }

        parts.append("cursor-agent")
        parts.append("--model \(shellEscape(model))")
        parts.append("--yolo")
        parts.append("--resume \(shellEscape(cursorSessionId))")
        parts.append("--output-format stream-json")
        parts.append("-p \(shellEscape(userPrompt))")
        parts.append("</dev/null")

        return parts.joined(separator: " ")
    }

    // MARK: - Session Warm-Up

    /// Ensures a cursor session exists for the given Pyre session ID.
    /// If no mapping exists, runs a warm-up prompt to create one.
    static func ensureSession(
        pyreSessionId: String,
        model: String,
        systemPrompt: String,
        workingDir: String?
    ) async throws -> String {
        if let existing = await CursorSessionRegistry.shared.get(pyreSessionId) {
            return existing
        }

        let warmupPrompt = buildWarmupPrompt(systemPrompt: systemPrompt)

        var parts: [String] = []
        if let dir = workingDir {
            parts.append("cd \(shellEscape(dir)) &&")
        }
        parts.append("cursor-agent")
        parts.append("--model \(shellEscape(model))")
        parts.append("--yolo")
        parts.append("--output-format json")
        parts.append("-p \(shellEscape(warmupPrompt))")
        parts.append("</dev/null")

        let command = parts.joined(separator: " ")
        let result = try await ShellExecutor.run(command)

        guard result.isSuccess else {
            throw LLMBackendError.sessionWarmupFailed("cursor-agent warmup exited non-zero: \(result.output)")
        }

        guard let cursorId = extractSessionId(result.output) else {
            throw LLMBackendError.sessionWarmupFailed("No session_id found in warmup output")
        }

        await CursorSessionRegistry.shared.put(pyreSessionId, cursorId: cursorId)
        DebugLogger.info("CursorCLI session mapped: \(pyreSessionId) -> \(cursorId)")

        return cursorId
    }

    // MARK: - Session ID Extraction

    /// Extracts session_id from cursor-agent JSON output.
    /// Handles both JSON array and NDJSON formats.
    static func extractSessionId(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try as JSON array
        if let data = trimmed.data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in items {
                if let id = item["session_id"] as? String, !id.isEmpty {
                    return id
                }
            }
        }

        // Try as NDJSON (line-by-line)
        for line in trimmed.components(separatedBy: "\n") where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["session_id"] as? String, !id.isEmpty {
                return id
            }
        }

        return nil
    }

    // MARK: - Private

    private static func buildWarmupPrompt(systemPrompt: String) -> String {
        if systemPrompt.isEmpty {
            return "You are being initialized for a new task session. Reply with: READY"
        }
        return """
        \(systemPrompt)

        You are being initialized for a new task session. Acknowledge that you \
        understand your role and are ready for the task prompt. Reply briefly with: READY
        """
    }

    private static func shellEscape(_ s: String) -> String {
        ClaudeCLIHelper.shellEscape(s)
    }
}
#endif
