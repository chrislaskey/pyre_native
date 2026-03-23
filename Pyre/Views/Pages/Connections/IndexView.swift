import SwiftUI
import Foundation
import Combine

// MARK: - ConnectionsIndexViewModel

class ConnectionsIndexViewModel: ObservableObject, PageViewModel {
    private(set) var router: URLRouter?
    private(set) var paramsFromRouter: ParamsFromRouter?

    @Published var connections: [Connection] = []
    @Published var currentConnectionId: String?

    init() {}

    func mount(_ paramsFromRouter: ParamsFromRouter, _ router: URLRouter) {
        self.router = router
        self.paramsFromRouter = paramsFromRouter

        handleParams()
    }

    func handleParams(_ payload: [String: Any] = [:]) {
        fetchConnections()
    }

    func reload() {
        handleParams()
    }

    func fetchConnections() {
        let all = ConnectionsService.list()
        connections = all.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        currentConnectionId = ConnectionsService.getCurrentConnectionId()
    }

    func selectConnection(_ id: String) {
        ConnectionsService.updateCurrentConnectionId(id)
        currentConnectionId = id
    }

    func deleteConnection(_ id: String) {
        ConnectionsService.delete(id: id)
        fetchConnections()
    }
}

// MARK: - ConnectionsIndexView

struct ConnectionsIndexView: View {
    @EnvironmentObject var router: URLRouter

    @StateObject private var viewModel = ConnectionsIndexViewModel()
    @State private var paramsFromRouter: ParamsFromRouter
    @State private var handledFirstOnAppear = false
    @State private var connectionToDelete: Connection?

    init(paramsFromRouter: ParamsFromRouter) {
        self.paramsFromRouter = paramsFromRouter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Connections")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Button {
                        router.navigate(to: "/connections/new")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }

                if viewModel.connections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No connections yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.connections) { connection in
                            connectionRow(connection)
                        }
                    }
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Delete Connection",
            isPresented: Binding(
                get: { connectionToDelete != nil },
                set: { if !$0 { connectionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let connection = connectionToDelete {
                    viewModel.deleteConnection(connection.id)
                    connectionToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                connectionToDelete = nil
            }
        } message: {
            if let connection = connectionToDelete {
                Text("Are you sure you want to delete \"\(connection.name)\"? This cannot be undone.")
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

    @ViewBuilder
    private func connectionRow(_ connection: Connection) -> some View {
        let isCurrent = viewModel.currentConnectionId == connection.id

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(connection.name)
                        .font(.headline)
                    if isCurrent {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }
                Text(connection.baseUrl)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !isCurrent {
                Button {
                    viewModel.selectConnection(connection.id)
                } label: {
                    Text("Use")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            }

            Button {
                router.navigate(to: "/connections/\(connection.id)")
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button {
                connectionToDelete = connection
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color.green.opacity(0.05) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    ConnectionsIndexView(paramsFromRouter: ParamsFromRouter(url: URL(string: "/connections")!, path: "/connections", template: "/connections", params: [:]))
}
