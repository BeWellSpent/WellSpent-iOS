import Foundation
import SwiftUI
import WellSpentAPI

/// Content for the "Manage" section: budget header (cycle/period), People and
/// Income drill-down, and the edit/delete-budget actions. Wrapped in its own
/// `NavigationStack` by the caller so its push state (e.g. into People/Income)
/// is independent of the other tabs/sidebar sections.
struct BudgetManageView: View {
    let viewModel: BudgetDetailViewModel
    let authenticatedClient: ProtocolClient?
    let currencyCode: String
    let localeIdentifier: String
    let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    /// Called after a successful delete. Deliberately a closure captured by
    /// the caller from *its own* outer scope, not a locally-declared
    /// `@Environment(\.dismiss)` here — this view sits inside its own nested
    /// `NavigationStack`, so a local `dismiss()` would only pop within that
    /// stack rather than removing the whole budget detail screen from the
    /// budget list's stack.
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
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("peopleNavLink")

                    NavigationLink("Income") {
                        IncomeListView(
                            budgetProfileID: viewModel.profile.id,
                            budgetCountryCode: viewModel.profile.countryCode,
                            authenticatedClient: authenticatedClient,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier
                        )
                    }
                    .accessibilityIdentifier("incomeNavLink")

                    NavigationLink("Savings") {
                        SavingsListView(
                            budgetProfileID: viewModel.profile.id,
                            periodStartDate: viewModel.currentPeriod?.startDate.date,
                            authenticatedClient: authenticatedClient,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier
                        )
                    }
                    .accessibilityIdentifier("savingsNavLink")

                    NavigationLink("Categories") {
                        CategoriesListView(
                            budgetProfileID: viewModel.profile.id,
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("categoriesNavLink")

                    NavigationLink("Payment Methods") {
                        PaymentMethodsListView(
                            budgetProfileID: viewModel.profile.id,
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("paymentMethodsNavLink")

                    NavigationLink("Invitations") {
                        InvitesListView(
                            budgetProfileID: viewModel.profile.id,
                            budgetOwnerUserID: viewModel.profile.userID,
                            authenticatedClient: authenticatedClient
                        )
                    }
                    .accessibilityIdentifier("invitationsNavLink")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.profile.name)
        .toolbar {
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
        let start = period.startDate.date.formatted(date: .abbreviated, time: .omitted)
        let end = period.endDate.date.formatted(date: .abbreviated, time: .omitted)
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
