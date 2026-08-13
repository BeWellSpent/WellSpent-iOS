import LinkKit
import SwiftUI
import WellSpentAPI

/// The Plaid connection list, used by both screens that show one.
///
/// With no `budgetProfileID` it is the caller's own connections across every
/// budget, embedded in `SettingsView`'s "Connected Bank Accounts" section
/// (US-only, matching web's `{isUS && <PlaidSection />}`). With one, it is
/// every member's connections on that budget, reached from `BudgetManageView`
/// — a broken connection stops transactions for everyone on the budget, but
/// only its owner could previously see it.
///
/// One view with a mode rather than two: only the query scope, the row
/// captions, and whether connecting needs a budget picker actually differ.
///
/// LinkKit (confirmed against the resolved package's own `.swiftinterface`,
/// not assumed) ships `PlaidLinkSession.sheet() -> some View` directly — no
/// `UIViewControllerRepresentable` wrapping needed, and no custom
/// `onOpenURL` routing for OAuth institutions either: current LinkKit
/// versions handle that continuation internally via
/// `ASWebAuthenticationSession` as long as `redirect_uri` was set correctly
/// when the token was created (see `PlaidConnectionsViewModel.redirectURI`).
struct PlaidConnectionsView: View {
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
    /// Supplied by Settings, which has already fetched it. Left nil elsewhere,
    /// in which case the view model resolves it.
    var plan: Wellspent_V1_AccountPlan?
    /// Non-nil scopes the list to one budget and skips the budget picker when
    /// connecting, since the target is already known.
    var budgetProfileID: String?

    @State private var viewModel: PlaidConnectionsViewModel?
    @State private var activeSheet: ActiveSheet?
    @State private var confirmDisconnect: Wellspent_V1_PlaidConnection?
    @State private var confirmResync: Wellspent_V1_PlaidConnection?
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
                viewModel = PlaidConnectionsViewModel(
                    authenticatedClient: authenticatedClient,
                    budgetProfileID: budgetProfileID,
                    plan: plan
                )
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
        .confirmationDialog(
            "Re-sync this bank?",
            isPresented: Binding(
                get: { confirmResync != nil },
                set: { if !$0 { confirmResync = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Re-sync") {
                if let confirmResync {
                    Task { await viewModel?.resync(confirmResync) }
                }
                self.confirmResync = nil
            }
        } message: {
            // Deliberately not "this may create duplicates" — it can't.
            // plaid_transaction_id is unique and already-imported rows are
            // skipped. What a replay really does is bring back transactions
            // the user deleted, which is the risk they can act on.
            Text("WellSpent will ask for this bank's full transaction history again, starting now. Transactions you deleted will come back. Ones already imported won't be duplicated. Available once a day per bank.")
        }
    }

    @ViewBuilder
    private func content(viewModel: PlaidConnectionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = viewModel.errorMessage ?? linkSessionErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.isFree {
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
            PlaidSyncWarningView(warnings: viewModel.visibleWarnings)

            if viewModel.isLoading && viewModel.connections.isEmpty {
                ProgressView()
            } else if viewModel.connections.isEmpty {
                (budgetProfileID == nil
                    ? Text("No banks connected yet.")
                    : Text("No bank accounts are connected to this budget yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.connections, id: \.id) { connection in
                    PlaidConnectionRow(
                        connection: connection,
                        subtitle: viewModel.subtitle(for: connection),
                        isManagingAccounts: viewModel.managingAccountsConnectionID == connection.id,
                        isDisconnecting: viewModel.disconnectingConnectionID == connection.id,
                        isResyncing: viewModel.resyncingConnectionID == connection.id,
                        manageAccountsDisabled: viewModel.isFree,
                        onManageAccounts: {
                            Task { await viewModel.startManageAccounts(connection) }
                        },
                        onDisconnect: {
                            confirmDisconnect = connection
                        },
                        onResync: {
                            confirmResync = connection
                        }
                    )
                    if connection.id != viewModel.connections.last?.id {
                        Divider()
                    }
                }
            }

            Button {
                // A budget-scoped screen already knows the target, so there
                // is nothing to pick.
                if let budgetProfileID {
                    Task { await viewModel.startConnect(budgetProfileID: budgetProfileID) }
                } else {
                    activeSheet = .pickBudget
                }
            } label: {
                Label("Connect a Bank", systemImage: "building.columns")
            }
            .disabled(viewModel.isFree)
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

#Preview("Settings — all budgets") {
    Form {
        Section("Connected Bank Accounts") {
            PlaidConnectionsView(
                authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
                plan: .free
            )
        }
    }
}

#Preview("One budget") {
    Form {
        PlaidConnectionsView(
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            plan: .lifetime,
            budgetProfileID: "budget-1"
        )
    }
}
