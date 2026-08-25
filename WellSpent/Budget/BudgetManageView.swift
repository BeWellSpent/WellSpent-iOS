import Foundation
import SwiftUI
import WellSpentAPI

/// The manage panels: budget header (cycle/period), the People/Income/…
/// drill-downs, and edit/delete budget.
///
/// Pushed from `BudgetMenuSheet` since issue #60 — it used to be a bottom tab.
/// That move is why it owns its own `.toolbar` again: as a tab it sat inside
/// `BudgetDetailView`'s doubly-nested `NavigationStack`s, where an inner
/// toolbar never renders, so its Edit/Delete menu had to be hoisted into the
/// parent and flipped through `@Binding`s. A pushed destination inside the
/// sheet's own stack has a nav bar that renders normally, so the workaround
/// is gone and the state is local again.
struct BudgetManageView: View {
    let viewModel: BudgetDetailViewModel
    let authenticatedClient: ProtocolClient?
    let currencyCode: String
    let localeIdentifier: String
    let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    /// Called after a successful delete, so the presenting sheet can close
    /// and the home view underneath can fall back to its empty state.
    let dismissParent: () -> Void

    @State private var isEditSheetPresented = false
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        List {
            Section {
                LabeledContent("Cycle", value: BudgetCycleLabel.text(for: viewModel.profile.cycle))
                if let period = viewModel.currentPeriod {
                    LabeledContent("Current period", value: periodRangeText(period))
                } else if viewModel.isLoading {
                    ProgressView()
                }
            }

            Section {
                if let authenticatedClient {
                    NavigationLink("People") {
                        PeopleListView(
                            budgetProfileID: viewModel.profile.id,
                            budgetOwnerUserID: viewModel.profile.userID,
                            authenticatedClient: authenticatedClient,
                            canManageUsers: viewModel.canManageUsers
                        )
                    }
                    .accessibilityIdentifier("peopleNavLink")

                    NavigationLink("Income") {
                        IncomeListView(
                            budgetProfileID: viewModel.profile.id,
                            budgetCountryCode: viewModel.profile.countryCode,
                            authenticatedClient: authenticatedClient,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier,
                            canEdit: viewModel.canEdit
                        )
                    }
                    .accessibilityIdentifier("incomeNavLink")

                    NavigationLink("Savings") {
                        SavingsListView(
                            budgetProfileID: viewModel.profile.id,
                            periodStartDate: viewModel.currentPeriod?.startDate.dateOnly,
                            authenticatedClient: authenticatedClient,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier,
                            canEdit: viewModel.canEdit
                        )
                    }
                    .accessibilityIdentifier("savingsNavLink")

                    NavigationLink("Categories") {
                        CategoriesListView(
                            budgetProfileID: viewModel.profile.id,
                            authenticatedClient: authenticatedClient,
                            canEdit: viewModel.canEdit
                        )
                    }
                    .accessibilityIdentifier("categoriesNavLink")

                    NavigationLink("Payment Methods") {
                        PaymentMethodsListView(
                            budgetProfileID: viewModel.profile.id,
                            authenticatedClient: authenticatedClient,
                            canEdit: viewModel.canEdit
                        )
                    }
                    .accessibilityIdentifier("paymentMethodsNavLink")

                    if viewModel.canManageUsers {
                        NavigationLink("Invitations") {
                            InvitesListView(
                                budgetProfileID: viewModel.profile.id,
                                budgetOwnerUserID: viewModel.profile.userID,
                                authenticatedClient: authenticatedClient
                            )
                        }
                        .accessibilityIdentifier("invitationsNavLink")
                    }

                    NavigationLink("Alert Settings") {
                        AlertsListView(
                            budgetProfileID: viewModel.profile.id,
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("alertSettingsNavLink")

                    // Plaid is US-only — the backend refuses everyone else
                    // outright. The budget's country is propagated from its
                    // owner at creation, so no extra fetch is needed here.
                    if viewModel.profile.countryCode == "US" {
                        NavigationLink("Bank Connections") {
                            PlaidConnectionsPanelView(
                                authenticatedClient: authenticatedClient,
                                budgetProfileID: viewModel.profile.id
                            )
                        }
                        .accessibilityIdentifier("bankConnectionsNavLink")
                    }
                }
            }

            if let authenticatedClient {
                // Not role-gated — these are the caller's own view settings,
                // so a Viewer gets them too.
                Section("Preferences") {
                    NavigationLink("Preferences") {
                        PreferencesView(
                            budgetProfileID: viewModel.profile.id,
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("preferencesNavLink")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.canManageUsers {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit Budget") { isEditSheetPresented = true }
                        Button("Delete Budget", role: .destructive) { isDeleteConfirmationPresented = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("budgetDetailMenu")
                }
            }
        }
        .sheet(isPresented: $isEditSheetPresented) {
            if let authenticatedClient {
                EditBudgetSheet(profile: viewModel.profile, authenticatedClient: authenticatedClient) { updated in
                    viewModel.applyUpdatedProfile(updated)
                    onUpdated(updated)
                }
            }
        }
        .confirmationDialog("Delete this budget?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        dismissParent()
                    }
                }
            }
        }
    }

    private func periodRangeText(_ period: Wellspent_V1_BudgetPeriod) -> String {
        let start = period.startDate.dateOnly.formatted(date: .abbreviated, time: .omitted)
        let end = period.endDate.dateOnly.formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }
}

#Preview {
    let client = APIClient.makePublicClient(baseURL: "http://localhost:1")
    return NavigationStack {
        BudgetManageView(
            viewModel: BudgetDetailViewModel(
                profile: .with {
                    $0.id = "preview-budget"
                    $0.name = "Household Budget"
                    $0.cycle = .monthly
                    $0.countryCode = "US"
                },
                authenticatedClient: client
            ),
            authenticatedClient: client,
            currencyCode: "USD",
            localeIdentifier: "en",
            onUpdated: { _ in },
            dismissParent: {}
        )
    }
}
