import SwiftUI
import Foundation
import Combine

// MARK: - ConnectionsNewViewModel

class ConnectionsNewViewModel: ObservableObject, PageViewModel {
    private(set) var router: URLRouter?
    private(set) var paramsFromRouter: ParamsFromRouter?

    @Published var name: String = ""
    @Published var baseUrl: String = ""
    @Published var isSubmitting: Bool = false
    @Published var toast: ToastData?

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

    }

    func reload() {
        handleParams()
    }

    func submit() {
        guard isValid else { return }
        isSubmitting = true

        let connection = Connection(
            name: name.trimmingCharacters(in: .whitespaces),
            baseUrl: baseUrl.trimmingCharacters(in: .whitespaces)
        )
        let created = ConnectionsService.create(connection)

        isSubmitting = false

        if !created {
            toast = ToastData(message: "A connection with that name and URL already exists.", type: .error)
            return
        }

        ConnectionsService.updateCurrentConnectionId(connection.id)
        router?.navigate(to: RouterHelpers.getHomePath())
    }
}

// MARK: - ConnectionsNewView

struct ConnectionsNewView: View {
    @EnvironmentObject var router: URLRouter

    @StateObject private var viewModel = ConnectionsNewViewModel()
    @State private var paramsFromRouter: ParamsFromRouter
    @State private var handledFirstOnAppear = false

    init(paramsFromRouter: ParamsFromRouter) {
        self.paramsFromRouter = paramsFromRouter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("New Connection")
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
                    title: "Create Connection",
                    icon: "plus.circle.fill",
                    backgroundColor: .blue,
                    isLoading: viewModel.isSubmitting,
                    isDisabled: !viewModel.isValid
                ) {
                    viewModel.submit()
                }
            }
            .padding()
        }
        .toast($viewModel.toast)
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
    ConnectionsNewView(paramsFromRouter: ParamsFromRouter(url: URL(string: "/connections/new")!, path: "/connections/new", template: "/connections/new", params: [:]))
}
