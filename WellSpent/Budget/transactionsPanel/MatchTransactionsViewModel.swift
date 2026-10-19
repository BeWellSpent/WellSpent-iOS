import Observation
import WellSpentAPI
import WellSpentREST

/// Fixed-row counterpart to `MarkForReviewViewModel` — multi-select instead of one.
@MainActor
@Observable
final class MatchTransactionsViewModel {
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var variableTransactions: [Wellspent_V1_Transaction] = []
    private(set) var errorMessage: String?
    var selectedIDs: Set<String> = []

    let budgetPeriodID: String
    let budgetProfileID: String

    private let restClient: WellSpentREST.Client

    init(budgetPeriodID: String, budgetProfileID: String, restClient: WellSpentREST.Client) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.restClient = restClient
    }

    var selectedTotal: (units: Int64, nanos: Int32) {
        let amounts = variableTransactions
            .filter { selectedIDs.contains($0.id) }
            .map { (units: $0.amount.units, nanos: $0.amount.nanos) }
        return TransactionAmountFormatting.sum(amounts)
    }

    /// Confirming only makes sense once the selection sums to the full amount.
    func matchesExactly(_ matchedTransaction: Wellspent_V1_Transaction) -> Bool {
        guard !selectedIDs.isEmpty else { return false }
        let total = selectedTotal
        return total.units == matchedTransaction.plannedAmount.units
            && total.nanos == matchedTransaction.plannedAmount.nanos
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let output = try await restClient.listTransactions(.init(query: .init(
                budgetPeriodId: budgetPeriodID,
                transactionType: BudgetRESTMapping.restExpenseType(from: TransactionsViewModel.variableTypeID)
            )))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load transactions."
                return
            }
            variableTransactions = body.transactions.map(BudgetRESTMapping.transaction(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load transactions."
        }
    }

    func setStateForTesting(variableTransactions: [Wellspent_V1_Transaction], selectedIDs: Set<String>) {
        self.variableTransactions = variableTransactions
        self.selectedIDs = selectedIDs
    }

    func matchSelected(to matchedTransaction: Wellspent_V1_Transaction) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        for transactionID in selectedIDs {
            let fallback = "Couldn't match that transaction."
            do {
                guard case .ok = try await restClient.markTransactionForReview(.init(
                    path: .init(id: transactionID),
                    body: .json(.init(matchedTransactionId: matchedTransaction.id, budgetProfileId: budgetProfileID))
                )) else {
                    errorMessage = fallback
                    return false
                }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                return false
            }
        }
        return true
    }
}
