import Foundation

#if os(macOS)
enum ShellExecutor {
    struct CommandResult: Sendable {
        let output: String
        let error: String
        let exitCode: Int32
    }

    /// Runs a shell command and returns its output.
    /// Dispatches blocking work to a background queue to avoid
    /// starving Swift concurrency's cooperative thread pool.
    nonisolated static func run(_ command: String) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()

                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = ["-c", command]
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()

                    // Read pipes before waitUntilExit to prevent deadlock on large output
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    process.waitUntilExit()

                    let result = CommandResult(
                        output: String(data: stdoutData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        error: String(data: stderrData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
