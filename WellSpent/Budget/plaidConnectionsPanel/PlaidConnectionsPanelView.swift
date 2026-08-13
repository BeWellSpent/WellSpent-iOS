import SwiftUI
import WellSpentAPI

/// The budget-scoped Plaid screen, pushed from `BudgetManageView`.
///
/// A thin wrapper: `PlaidConnectionsView` does the work, this only supplies
/// the screen chrome and the explanation of why other people's banks are
/// listed here at all.
struct PlaidConnectionsPanelView: View {
    let authenticatedClient: ProtocolClient
    let budgetProfileID: String

    var body: some View {
        Form {
            Section {
                PlaidConnectionsView(
                    authenticatedClient: authenticatedClient,
                    budgetProfileID: budgetProfileID
                )
            } footer: {
                Text("Bank connections feeding this budget, from everyone on it. You can only change your own.")
            }
        }
        .navigationTitle("Bank Connections")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("plaidConnectionsPanel")
    }
}

#Preview {
    NavigationStack {
        PlaidConnectionsPanelView(
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            budgetProfileID: "budget-1"
        )
    }
}
