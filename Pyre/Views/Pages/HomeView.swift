import SwiftUI
import Foundation
import Combine

#if os(macOS)
import Subprocess
#endif

// MARK: - HomeViewModel

class HomeViewModel: ObservableObject, PageViewModel {
    private(set) var router: URLRouter?
    private(set) var paramsFromRouter: ParamsFromRouter?

    init() {}
    
    func mount(_ paramsFromRouter: ParamsFromRouter, _ router: URLRouter) {
        self.router = router
        self.paramsFromRouter = paramsFromRouter

        handleParams()
    }
    
    func handleParams(_ payload: [String: Any] = [:]) {
        DebugLogger.info("Loading page data")
    }

    func reload() {
        handleParams()
    }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var router: URLRouter

    @StateObject private var viewModel = HomeViewModel()
    @State private var paramsFromRouter: ParamsFromRouter
    @State private var handledFirstOnAppear = false

    @State private var commandInput: String = ""
    @State private var commandOutput: String = ""
    @State private var isRunning = false
    @State private var hasRun = false
    #if os(macOS)
    @State private var currentExecution: Execution?
    #endif

    init(paramsFromRouter: ParamsFromRouter) {
        self.paramsFromRouter = paramsFromRouter
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "flame.fill")
                    .imageScale(.large)
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Pyre")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                #if os(macOS)
                HStack {
                    TextField("Enter a command…", text: $commandInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { runCommand() }
                        .disabled(isRunning)

                    if isRunning {
                        Button {
                            stopCommand()
                        } label: {
                            Image(systemName: "stop.fill")
                                .foregroundStyle(.red)
                        }
                        .controlSize(.large)
                    } else {
                        Button {
                            runCommand()
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .disabled(commandInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: 480)

                if hasRun {
                    GroupBox {
                        ScrollView {
                            Text(commandOutput)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                    } label: {
                        Label("Output", systemImage: "text.alignleft")
                    }
                    .frame(maxWidth: 480)
                }
                #else
                Text("Shell execution is only available on macOS")
                    .foregroundStyle(.secondary)
                #endif
            }
            .padding(32)
        }
        .withPageReloadable(viewModel: viewModel)
        .onAppear {
            if !handledFirstOnAppear {
                viewModel.mount(paramsFromRouter, router)
                handledFirstOnAppear = true
            }
        }
        .onDisappear {
            handledFirstOnAppear = false
        }
    }

    #if os(macOS)
    private func runCommand() {
        let command = commandInput.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }

        isRunning = true
        commandOutput = ""
        hasRun = true
        currentExecution = nil

        Task {
            do {
                let status = try await ShellExecutor.stream(
                    command,
                    onStart: { execution in
                        await MainActor.run {
                            currentExecution = execution
                        }
                    },
                    onLine: { line in
                        await MainActor.run {
                            if commandOutput.isEmpty {
                                commandOutput = line
                            } else {
                                commandOutput += "\n" + line
                            }
                        }
                    }
                )
                if !status.isSuccess {
                    let note = status.wasTerminatedBySignal ? "stopped" : "exit: \(status)"
                    commandOutput += commandOutput.isEmpty ? note : "\n\(note)"
                }
            } catch {
                commandOutput += "\nError: \(error.localizedDescription)"
            }
            isRunning = false
            currentExecution = nil
        }
    }

    private func stopCommand() {
        guard let execution = currentExecution else { return }
        Task {
            await ShellExecutor.stop(execution)
        }
    }
    #endif
}

#if os(macOS)
private extension TerminationStatus {
    var wasTerminatedBySignal: Bool {
        if case .unhandledException = self { return true }
        return false
    }
}
#endif

#Preview {
    HomeView(paramsFromRouter: ParamsFromRouter(url: URL(string: "/")!, path: "/", template: "/", params: [:]))
}
