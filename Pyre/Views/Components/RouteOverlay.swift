import SwiftUI

struct RouterOverlay: View {
    @ObservedObject var router: URLRouter
    @Environment(\.dismiss) private var dismiss
    @State private var path: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Go to Route")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("/route", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit { goToRoute() }

                Button("Go") { goToRoute() }
                    .buttonStyle(.borderedProminent)
                    .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            path = router.currentURL.path
            isTextFieldFocused = true
        }
    }

    private func goToRoute() {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        router.navigate(to: normalized)
        dismiss()
    }
}
