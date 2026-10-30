import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Pushed from `PeriodReviewGateView` into the previous period's
/// transactions — the previous period is not archived (same editable-window
/// rule as any other non-archived period), so this embeds the *real*
/// `TransactionsListView` unchanged rather than re-deriving its swipe
/// actions, mark/unmark-paid, exclude toggle, Plaid category-only lock, or
/// merged confirmed-match display. No add entry point is exposed here —
/// this screen is for reviewing/fixing what's already there, not adding to
/// it — so the two `@State` bindings below are never flipped `true`.
struct PeriodReviewTransactionsView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    var reviewViewModel: TransactionReviewViewModel? = nil

    @State private var isAddTransactionPresented = false
    @State private var isAddFixedExpensePresented = false

    var body: some View {
        TransactionsListView(
            budgetPeriodID: budgetPeriodID,
            budgetProfileID: budgetProfileID,
            authenticatedRESTClient: authenticatedRESTClient,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            isAddTransactionPresented: $isAddTransactionPresented,
            isAddFixedExpensePresented: $isAddFixedExpensePresented,
            isActive: true,
            reviewViewModel: reviewViewModel,
            canEdit: canEdit,
            isArchivedPeriod: false,
            searchQuery: ""
        )
    }
}

#Preview {
    NavigationStack {
        PeriodReviewTransactionsView(
            budgetPeriodID: "previous",
            budgetProfileID: "profile",
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en_US",
            canEdit: true
        )
    }
}
