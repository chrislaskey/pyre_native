import SwiftUI

struct ContentView: View {
    @State private var commandOutput: String = ""
    @State private var isRunning = false
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "flame.fill")
                .imageScale(.large)
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Pyre")
                .font(.largeTitle)
                .fontWeight(.bold)

            #if os(macOS)
            Button {
                runCommand()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                    Text(isRunning ? "Running…" : "Run pwd")
                }
            }
            .disabled(isRunning)
            .controlSize(.large)

            if hasRun {
                GroupBox {
                    ScrollView {
                        Text(commandOutput)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
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

    #if os(macOS)
    private func runCommand() {
        isRunning = true
        commandOutput = ""

        Task {
            do {
                let result = try await ShellExecutor.run("pwd")
                commandOutput = result.output
                if !result.error.isEmpty {
                    commandOutput += "\nstderr: \(result.error)"
                }
                if result.exitCode != 0 {
                    commandOutput += "\nexit code: \(result.exitCode)"
                }
            } catch {
                commandOutput = "Error: \(error.localizedDescription)"
            }
            isRunning = false
            hasRun = true
        }
    }
    #endif
}

#Preview {
    ContentView()
}
