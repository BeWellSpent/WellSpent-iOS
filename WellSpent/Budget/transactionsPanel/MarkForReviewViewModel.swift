import Observation
import WellSpentAPI

/// Mirrors web's `MarkForReviewDialog.tsx` — lets the user manually flag a
/// Variable transaction as matching one of the period's own Fixed-type
/// transactions (rather than waiting for Plaid's automatic scoring).
@MainActor
@Observable
final class MarkForReviewViewModel {
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var fixedTransactions: [Wellspent_V1_Transaction] = []
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient

    init(budgetPeriodID: String, budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response = await client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = FixedExpensesViewModel.fixedTypeID
        })
        switch response.result {
        case .success(let message):
            fixedTransactions = message.transactions
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load fixed expenses."
        }
    }

    func markForReview(transaction: Wellspent_V1_Transaction, matchedTransaction: Wellspent_V1_Transaction) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let response = await client.markTransactionForReview(request: .with {
            $0.transactionID = transaction.id
            $0.matchedTransactionID = matchedTransaction.id
            $0.budgetProfileID = budgetProfileID
        })

        switch response.result {
        case .success:
            return true
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't flag that transaction."
            return false
        }
    }
}
