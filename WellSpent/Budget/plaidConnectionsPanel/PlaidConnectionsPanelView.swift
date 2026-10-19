import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The budget-scoped Plaid screen, pushed from `BudgetManageView`.
///
/// A thin wrapper: `PlaidConnectionsView` does the work, this only supplies
/// the screen chrome and the explanation of why other people's banks are
/// listed here at all.
struct PlaidConnectionsPanelView: View {
    let authenticatedRESTClient: WellSpentREST.Client
    let budgetProfileID: String

    var body: some View {
        Form {
            Section {
                PlaidConnectionsView(
                    authenticatedRESTClient: authenticatedRESTClient,
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
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            budgetProfileID: "budget-1"
        )
    }
}
