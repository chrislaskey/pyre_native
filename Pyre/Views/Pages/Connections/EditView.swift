import SwiftUI
import Foundation
import Combine

// MARK: - ConnectionsEditViewModel

class ConnectionsEditViewModel: ObservableObject, PageViewModel {
    private(set) var router: URLRouter?
    private(set) var paramsFromRouter: ParamsFromRouter?

    @Published var connectionId: String = ""
    @Published var name: String = ""
    @Published var baseUrl: String = ""
    @Published var isSubmitting: Bool = false
    @Published var notFound: Bool = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !baseUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {}

    func mount(_ paramsFromRouter: ParamsFromRouter, _ router: URLRouter) {
        self.router = router
        self.paramsFromRouter = paramsFromRouter

        handleParams()
    }

    func handleParams(_ payload: [String: Any] = [:]) {
        guard let id = paramsFromRouter?.params["id"],
              let connection = ConnectionsService.get(id: id) else {
            notFound = true
            return
        }

        connectionId = connection.id
        name = connection.name
        baseUrl = connection.baseUrl
    }

    func reload() {
        handleParams()
    }

    func submit() {
        guard isValid, !connectionId.isEmpty else { return }
        isSubmitting = true

        let connection = Connection(
            id: connectionId,
            name: name.trimmingCharacters(in: .whitespaces),
            baseUrl: baseUrl.trimmingCharacters(in: .whitespaces)
        )
        ConnectionsService.update(connection)

        isSubmitting = false
        router?.navigate(to: "/connections")
    }
}

// MARK: - ConnectionsEditView

struct ConnectionsEditView: View {
    @EnvironmentObject var router: URLRouter

    @StateObject private var viewModel = ConnectionsEditViewModel()
    @State private var paramsFromRouter: ParamsFromRouter
    @State private var handledFirstOnAppear = false

    init(paramsFromRouter: ParamsFromRouter) {
        self.paramsFromRouter = paramsFromRouter
    }

    var body: some View {
        ScrollView {
            if viewModel.notFound {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Connection not found")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Edit Connection")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("My Server", text: $viewModel.name)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { if viewModel.isValid { viewModel.submit() } }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base URL")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("https://example.com", text: $viewModel.baseUrl)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .autocapitalization(.none)
                                #endif
                                .disableAutocorrection(true)
                                .onSubmit { if viewModel.isValid { viewModel.submit() } }
                        }
                    }

                    ActionButton(
                        title: "Save Connection",
                        icon: "checkmark.circle.fill",
                        backgroundColor: .blue,
                        isLoading: viewModel.isSubmitting,
                        isDisabled: !viewModel.isValid
                    ) {
                        viewModel.submit()
                    }
                }
                .padding()
            }
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
}

#Preview {
    ConnectionsEditView(paramsFromRouter: ParamsFromRouter(url: URL(string: "/connections/123")!, path: "/connections/123", template: "/connections/:id", params: ["id": "123"]))
}
