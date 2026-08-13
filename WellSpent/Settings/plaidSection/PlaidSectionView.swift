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
    /// Everything `PlaidSectionView` can present, consolidated into a single
    /// `.sheet(item:)`. Previously this view stacked two independent
    /// `.sheet(isPresented:)` modifiers (budget picker + Plaid Link) on the
    /// same view — a known SwiftUI footgun: with more than one `.sheet`
    /// modifier on one view, SwiftUI can only reliably track one active
    /// presentation, so state changes across the others get cross-wired
    /// (symptoms reported live: the first tap on "Connect a Bank" silently
    /// did nothing and needed a second tap; tapping a row's "manage
    /// accounts" could surface the wrong sheet). A single enum-driven
    /// `.sheet(item:)` removes the ambiguity entirely.
    enum ActiveSheet: Identifiable {
        case pickBudget
        case plaidLink(PlaidLinkSession)

        var id: String {
            switch self {
            case .pickBudget: return "pickBudget"
            case .plaidLink: return "plaidLink"
            }
        }
    }

    let authenticatedClient: ProtocolClient
    let plan: Wellspent_V1_AccountPlan

    @State private var viewModel: PlaidSectionViewModel?
    @State private var activeSheet: ActiveSheet?
    @State private var confirmDisconnect: Wellspent_V1_PlaidConnection?
    @State private var linkSessionErrorMessage: String?

    private var isFree: Bool { plan == .unspecified || plan == .free }

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
            guard let newToken else { return }
            createLinkSession(token: newToken)
        }
        .sheet(item: $activeSheet, onDismiss: {
            viewModel?.handleLinkExit()
        }) { sheet in
            switch sheet {
            case .pickBudget:
                BudgetPickerSheet(budgets: viewModel?.budgets ?? []) { budgetID in
                    activeSheet = nil
                    Task { await viewModel?.startConnect(budgetProfileID: budgetID) }
                }
            case .plaidLink(let session):
                session.sheet()
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

            if isFree {
                Text("Only available on Pro accounts")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            // Above the list deliberately: these concern connections that
            // aren't in the list at all, since this screen only ever shows
            // the caller's own.
            PlaidSyncWarningView(warnings: viewModel.syncWarnings)

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
                        manageAccountsDisabled: isFree,
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
                activeSheet = .pickBudget
            } label: {
                Label("Connect a Bank", systemImage: "building.columns")
            }
            .disabled(isFree)
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
            activeSheet = .plaidLink(try Plaid.createPlaidLinkSession(configuration: configuration))
        } catch {
            linkSessionErrorMessage = error.localizedDescription
            viewModel?.handleLinkExit()
        }
    }
}

#Preview {
    Form {
        Section("Connected Bank Accounts") {
            PlaidSectionView(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"), plan: .free)
        }
    }
}
