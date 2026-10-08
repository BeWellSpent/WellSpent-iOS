import Observation
import WellSpentAPI

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

    private let client: Wellspent_V1_BudgetServiceClient

    init(budgetPeriodID: String, budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
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

        let response = await client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = TransactionsViewModel.variableTypeID
        })
        switch response.result {
        case .success(let message):
            variableTransactions = message.transactions
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load transactions."
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
            let response = await client.markTransactionForReview(request: .with {
                $0.transactionID = transactionID
                $0.matchedTransactionID = matchedTransaction.id
                $0.budgetProfileID = budgetProfileID
            })
            if case .failure(let error) = response.result {
                errorMessage = error.message ?? "Couldn't match that transaction."
                return false
            }
        }
        return true
    }
}
