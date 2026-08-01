import LinkKit
import SwiftUI
import WellSpentAPI

/// Mirrors web's `PlaidSection.tsx` orchestrator. Embedded as a
/// self-contained subview inside `SettingsView`'s "Connected Bank Accounts"
/// section (US-only, matching `ProfileSettings.tsx`'s `{isUS && <PlaidSection />}`).
///
/// LinkKit (confirmed against the resolved package's own `.swiftinterface`,
/// not assumed) ships `PlaidLinkSession.sheet() -> some View` directly — no
/// `UIViewControllerRepresentable` wrapping needed, and no custom
/// `onOpenURL` routing for OAuth institutions either: current LinkKit
/// versions handle that continuation internally via
/// `ASWebAuthenticationSession` as long as `redirect_uri` was set correctly
/// when the token was created (see `PlaidSectionViewModel.redirectURI`).
struct PlaidSectionView: View {
    let authenticatedClient: ProtocolClient

    @State private var viewModel: PlaidSectionViewModel?
    @State private var isPickingBudget = false
    @State private var confirmDisconnect: Wellspent_V1_PlaidConnection?
    @State private var linkSession: PlaidLinkSession?
    @State private var linkSessionErrorMessage: String?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = PlaidSectionViewModel(authenticatedClient: authenticatedClient)
            }
            await viewModel?.load()
        }
        .onChange(of: viewModel?.activeLinkToken) { _, newToken in
            guard let newToken else {
                linkSession = nil
                return
            }
            createLinkSession(token: newToken)
        }
        .sheet(isPresented: Binding(
            get: { linkSession != nil },
            set: { if !$0 { viewModel?.handleLinkExit() } }
        )) {
            if let linkSession {
                linkSession.sheet()
            }
        }
        .sheet(isPresented: $isPickingBudget) {
            BudgetPickerSheet(budgets: viewModel?.budgets ?? []) { budgetID in
                isPickingBudget = false
                Task { await viewModel?.startConnect(budgetProfileID: budgetID) }
            }
        }
        .confirmationDialog(
            "Disconnect this bank?",
            isPresented: Binding(
                get: { confirmDisconnect != nil },
                set: { if !$0 { confirmDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                if let confirmDisconnect {
                    Task { await viewModel?.disconnect(confirmDisconnect) }
                }
                self.confirmDisconnect = nil
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: PlaidSectionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = viewModel.errorMessage ?? linkSessionErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.isLoading && viewModel.connections.isEmpty {
                ProgressView()
            } else if viewModel.connections.isEmpty {
                Text("No banks connected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.connections, id: \.id) { connection in
                    PlaidConnectionRow(
                        connection: connection,
                        budgetName: viewModel.budgetName(for: connection.budgetProfileID),
                        isManagingAccounts: viewModel.managingAccountsConnectionID == connection.id,
                        isDisconnecting: viewModel.disconnectingConnectionID == connection.id,
                        onManageAccounts: {
                            Task { await viewModel.startManageAccounts(connection) }
                        },
                        onDisconnect: {
                            confirmDisconnect = connection
                        }
                    )
                    if connection.id != viewModel.connections.last?.id {
                        Divider()
                    }
                }
            }

            Button {
                isPickingBudget = true
            } label: {
                Label("Connect a Bank", systemImage: "building.columns")
            }
            .accessibilityIdentifier("connectBankButton")
        }
    }

    private func createLinkSession(token: String) {
        let configuration = LinkTokenConfiguration(
            token: token,
            onSuccess: { linkSuccess in
                Task { await viewModel?.handleLinkSuccess(publicToken: linkSuccess.publicToken) }
            },
            onExit: { linkExit in
                if let error = linkExit.error {
                    linkSessionErrorMessage = error.errorMessage
                }
                viewModel?.handleLinkExit()
            },
            onEvent: nil,
            onLoad: nil
        )

        do {
            linkSession = try Plaid.createPlaidLinkSession(configuration: configuration)
        } catch {
            linkSessionErrorMessage = error.localizedDescription
            viewModel?.handleLinkExit()
        }
    }
}

#Preview {
    Form {
        Section("Connected Bank Accounts") {
            PlaidSectionView(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
        }
    }
}
