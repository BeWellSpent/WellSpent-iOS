import Observation
import WellSpentAPI
import WellSpentREST

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
    private let restClient: WellSpentREST.Client

    init(budgetPeriodID: String, budgetProfileID: String, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.listTransactions(.init(query: .init(
                    budgetPeriodId: budgetPeriodID,
                    transactionType: BudgetRESTMapping.restExpenseType(from: FixedExpensesViewModel.fixedTypeID)
                )))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load fixed expenses."
                    return
                }
                fixedTransactions = body.transactions.map(BudgetRESTMapping.transaction(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load fixed expenses."
            }
            return
        }

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
