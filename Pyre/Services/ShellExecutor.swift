#if os(macOS)
import Darwin
import Foundation
import Subprocess
import Synchronization
import System

// MARK: - Process Tracking

/// Tracks PIDs of spawned process groups so they can be
/// killed on app termination (preventing orphaned processes).
final class ProcessTracker: Sendable {
    nonisolated static let shared = ProcessTracker()
    private let state = Mutex<Set<pid_t>>([])

    nonisolated func track(_ pid: pid_t) {
        state.withLock { _ = $0.insert(pid) }
    }

    nonisolated func untrack(_ pid: pid_t) {
        state.withLock { _ = $0.remove(pid) }
    }

    /// Immediately kills all tracked process trees. Called during app termination.
    nonisolated func killAll() {
        let snapshot = state.withLock { pids -> Set<pid_t> in
            let copy = pids
            pids.removeAll()
            return copy
        }
        for pid in snapshot {
            Self.killTree(pid, signal: SIGKILL)
        }
    }

    /// Recursively finds all descendant PIDs of the given process.
    /// Returns children-first order so leaves are killed before parents.
    nonisolated static func collectDescendants(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var buffer = [pid_t](repeating: 0, count: 4096)
        let bufferSize = Int32(buffer.count * MemoryLayout<pid_t>.stride)
        let count = proc_listchildpids(pid, &buffer, bufferSize)

        guard count > 0 else { return result }

        for i in 0..<Int(count) {
            let childPID = buffer[i]
            guard childPID > 0 else { continue }
            result += collectDescendants(of: childPID)
            result.append(childPID)
        }

        return result
    }

    /// Sends a signal to every process in the tree rooted at `pid`,
    /// plus the process group (in case any children share the group).
    nonisolated static func killTree(_ pid: pid_t, signal: Int32) {
        let descendants = collectDescendants(of: pid)
        for p in descendants {
            kill(p, signal)
        }
        kill(pid, signal)
        kill(-pid, signal)
    }
}

// MARK: - Shell Executor

enum ShellExecutor {
    struct CommandResult: Sendable {
        let output: String
        let error: String
        let terminationStatus: TerminationStatus

        var isSuccess: Bool { terminationStatus.isSuccess }
    }

    private nonisolated static var userShell: FilePath {
        FilePath(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    }

    /// Platform options that make the child its own process group leader.
    private nonisolated static var spawnOptions: PlatformOptions {
        var opts = PlatformOptions()
        opts.processGroupID = 0
        return opts
    }

    /// Runs a shell command and collects its output.
    nonisolated static func run(_ command: String) async throws -> CommandResult {
        let result = try await Subprocess.run(
            .path(userShell),
            arguments: ["-ilc", command],
            platformOptions: spawnOptions,
            output: .string(limit: 1_048_576),
            error: .string(limit: 1_048_576)
        )

        return CommandResult(
            output: (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            error: filterShellNoise(result.standardError ?? ""),
            terminationStatus: result.terminationStatus
        )
    }

    /// Runs a shell command and streams stdout line-by-line.
    /// Stderr is merged into the output stream so everything appears in order.
    nonisolated static func stream(
        _ command: String,
        onStart: @escaping @Sendable (Execution) async -> Void,
        onLine: @escaping @Sendable (String) async -> Void
    ) async throws -> TerminationStatus {
        let executionResult = try await Subprocess.run(
            .path(userShell),
            arguments: ["-ilc", command],
            platformOptions: spawnOptions,
            error: .combineWithOutput,
            preferredBufferSize: 1
        ) { (execution: Execution, standardOutput: AsyncBufferSequence) -> pid_t in
            let pid = execution.processIdentifier.value
            ProcessTracker.shared.track(pid)
            await onStart(execution)
            for try await line in standardOutput.lines() {
                let cleaned = line.trimmingCharacters(in: .newlines)
                guard !cleaned.isEmpty, !isShellNoise(cleaned) else { continue }
                await onLine(cleaned)
            }
            return pid
        }

        ProcessTracker.shared.untrack(executionResult.value)
        return executionResult.terminationStatus
    }

    /// Gracefully stops a running process tree: SIGTERM everything,
    /// wait 2 seconds, then SIGKILL any survivors.
    nonisolated static func stop(_ execution: Execution) async {
        let pid = execution.processIdentifier.value
        ProcessTracker.killTree(pid, signal: SIGTERM)
        try? await Task.sleep(for: .seconds(2))
        ProcessTracker.killTree(pid, signal: SIGKILL)
    }

    private nonisolated static func isShellNoise(_ line: String) -> Bool {
        line.contains("cannot set terminal process group") ||
        line.contains("no job control in this shell")
    }

    private nonisolated static func filterShellNoise(_ stderr: String) -> String {
        stderr
            .components(separatedBy: "\n")
            .filter { !isShellNoise($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
