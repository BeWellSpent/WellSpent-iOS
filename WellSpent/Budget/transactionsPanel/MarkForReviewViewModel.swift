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

    private let restClient: WellSpentREST.Client

    init(budgetPeriodID: String, budgetProfileID: String, restClient: WellSpentREST.Client) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

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
    }

    func markForReview(transaction: Wellspent_V1_Transaction, matchedTransaction: Wellspent_V1_Transaction) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let fallback = "Couldn't flag that transaction."
        do {
            guard case .ok = try await restClient.markTransactionForReview(.init(
                path: .init(id: transaction.id),
                body: .json(.init(matchedTransactionId: matchedTransaction.id, budgetProfileId: budgetProfileID))
            )) else {
                errorMessage = fallback
                return false
            }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }
}
