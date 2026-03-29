#if os(macOS)
import Foundation
import Combine
import Subprocess

/// Handles remote command execution requests from the server.
/// Runs commands via ShellExecutor and streams output back over the channel.
@MainActor
final class RemoteCommandService: ObservableObject {
    static let shared = RemoteCommandService()

    @Published private(set) var currentExecution: RemoteExecution?
    @Published private(set) var isRunning = false

    struct RemoteExecution: Identifiable {
        let id: String
        var commands: [String]
        var currentCommandIndex: Int = 0
        var output: String = ""
        var exitCodes: [Int32] = []
        var status: Status = .running

        enum Status { case running, complete, error, stopped }
    }

    private var currentProcessExecution: Execution?

    func execute(
        commands: [String],
        executionId: String,
        channel: PhoenixChannelLiveView
    ) {
        guard !isRunning else { return }

        isRunning = true
        currentExecution = RemoteExecution(id: executionId, commands: commands)

        Task { [weak self] in
            var exitCodes: [Int32] = []

            for (index, command) in commands.enumerated() {
                await MainActor.run { self?.currentExecution?.currentCommandIndex = index }

                do {
                    let status = try await ShellExecutor.stream(
                        command,
                        onStart: { execution in
                            await MainActor.run {
                                self?.currentProcessExecution = execution
                            }
                        },
                        onLine: { line in
                            await MainActor.run {
                                self?.currentExecution?.output += line + "\n"

                                channel.pushAsync("action_output", [
                                    "execution_id": executionId,
                                    "line": line,
                                    "command_index": index
                                ])
                            }
                        }
                    )

                    let code = status.isSuccess ? Int32(0) : Int32(1)
                    exitCodes.append(code)

                    if code != 0 {
                        break
                    }
                } catch {
                    self?.currentExecution?.output += "Error: \(error.localizedDescription)\n"
                    exitCodes.append(1)
                    break
                }
            }

            channel.pushAsync("action_complete", [
                "execution_id": executionId,
                "exit_codes": exitCodes
            ])

            self?.currentExecution?.exitCodes = exitCodes
            self?.currentExecution?.status = exitCodes.allSatisfy({ $0 == 0 })
                ? .complete : .error
            self?.isRunning = false
            self?.currentProcessExecution = nil
        }
    }

    func stop() {
        guard let execution = currentProcessExecution else { return }
        Task {
            await ShellExecutor.stop(execution)
            currentExecution?.status = .stopped
            isRunning = false
        }
    }
}
#endif
