import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class TransactionsViewModel {
    /// `transaction_type` lookup table seed order (see
    /// WellSpent-backend/internal/db/migrations/000001_init_schema.sql):
    /// Fixed = 1, Variable = 2. Raw int32 on the wire, no proto enum.
    static let variableTypeID: Int32 = 2

    private(set) var isLoading = false
    private(set) var transactions: [Wellspent_V1_Transaction] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    /// Totals and the over-budget set, computed server-side. Replaces four
    /// fetches (allocations, savings sources, fixed transactions, and the
    /// planned-total rule applied to them) that existed only to rebuild
    /// figures this one response already carries.
    private(set) var summary: Wellspent_V1_GetExpenseSummaryResponse?
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String

    private let client: Wellspent_V1_BudgetServiceClient

    /// Which transactions crossed their category's plan — server-computed.
    ///
    /// This used to walk the transactions locally against a baseline built
    /// from `ExpensePlanCalculations.plannedTotal`, the last surviving copy of
    /// the math `GetExpenseSummary` replaced everywhere else (issue #35). Web
    /// built its own too, and the two disagreed on whether an allocation and a
    /// fixed bill in one category add together or fall back. Now neither
    /// derives it (#61).
    var overBudgetTransactionIDs: Set<String> {
        Set(summary?.overBudgetTransactionIds ?? [])
    }

    /// Variable spend for the period, server-computed under the same
    /// exclusion rule as everywhere else — manually excluded rows and the
    /// system "Income" category never count. Summing the fetched rows here
    /// instead would put a second spelling of the number next to the totals
    /// the Plan and Overview tabs print.
    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: [TransactionAmountFormatting.tuple(from: summary?.variableActualTotal)],
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, authenticatedClient: ProtocolClient) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let transactionsResponse = client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = Self.variableTypeID
        })
        async let categoriesResponse = client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let summaryResponse = client.getExpenseSummary(request: .with { $0.budgetPeriodID = budgetPeriodID })

        switch await transactionsResponse.result {
        case .success(let message):
            transactions = message.transactions.sorted { $0.date.date > $1.date.date }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load transactions."
        }

        if case .success(let message) = await categoriesResponse.result {
            categories = message.categories
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
        if case .success(let message) = await summaryResponse.result {
            summary = message
        }
    }

    /// Excludes transactions whose review was confirmed — those are shown
    /// instead as a linked sub-row under the matched Fixed transaction (see
    /// `TransactionReviewMatching`).
    func visibleTransactions(reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_Transaction] {
        let confirmedIDs = TransactionReviewMatching.confirmedTransactionIDs(reviews)
        return transactions.filter { !confirmedIDs.contains($0.id) }
    }

    func pendingMatchName(for transaction: Wellspent_V1_Transaction, reviews: [Wellspent_V1_TransactionReview]) -> String? {
        TransactionReviewMatching.pendingMatchName(forTransactionID: transaction.id, reviews: reviews)
    }

    /// The translated name, so a row's caption and the search that has to
    /// match it both use what is actually on screen.
    func categoryName(for categoryID: Int32) -> String? {
        guard categoryID != 0 else { return nil }
        return categories.first(where: { $0.id == categoryID })?.displayName
    }

    func categoryColor(for categoryID: Int32) -> String {
        categories.first(where: { $0.id == categoryID })?.color ?? ""
    }

    func paymentMethodName(for paymentMethodID: String) -> String? {
        guard !paymentMethodID.isEmpty else { return nil }
        guard let method = paymentMethods.first(where: { $0.id == paymentMethodID }) else { return nil }
        return method.alias.isEmpty ? method.name : method.alias
    }

    func paymentMethodColor(for paymentMethodID: String) -> String {
        paymentMethods.first(where: { $0.id == paymentMethodID })?.color ?? ""
    }

    /// Resolves a transaction's owner via its payment method's attributed
    /// person — mirrors web's `resolveOwnerName`. Used by search, not display.
    func ownerName(for paymentMethodID: String) -> String? {
        guard !paymentMethodID.isEmpty else { return nil }
        guard let method = paymentMethods.first(where: { $0.id == paymentMethodID }), method.budgetPersonID != 0 else { return nil }
        return people.first(where: { $0.id == method.budgetPersonID })?.userName
    }

    func addTransaction(_ transaction: Wellspent_V1_Transaction) {
        transactions.insert(transaction, at: 0)
    }

    func replaceTransaction(_ transaction: Wellspent_V1_Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }

    /// Reverses an installment split. The backend refuses once any payment has
    /// been marked paid — real recorded spend shouldn't vanish into an undo —
    /// so that failure is an expected outcome here and its message is shown
    /// as-is rather than replaced with a generic one.
    ///
    /// Reloads rather than patching local state: the plan's spawned payments
    /// are deleted server-side too, and they may sit in periods this list
    /// isn't showing.
    func deleteInstallmentPlan(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let response = await client.deleteInstallmentPlan(request: .with {
            $0.transactionID = transaction.id
            $0.budgetPeriodID = budgetPeriodID
        })

        switch response.result {
        case .success:
            await load()
        case .failure(let error):
            errorMessage = error.message ?? String(
                localized: "Couldn't undo the split.",
                locale: AppLanguageStore.currentLocale
            )
        }
    }

    func toggleExcluded(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let request = Wellspent_V1_SetTransactionExcludedRequest.with {
            $0.id = transaction.id
            $0.budgetPeriodID = budgetPeriodID
            $0.excluded = !transaction.isExcluded
        }
        let response = await client.setTransactionExcluded(request: request)

        switch response.result {
        case .success:
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                transactions[index].isExcluded.toggle()
            }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that transaction."
        }
    }

    func delete(id: String) async {
        errorMessage = nil
        let request = Wellspent_V1_DeleteTransactionRequest.with {
            $0.id = id
            $0.budgetPeriodID = budgetPeriodID
        }
        let response = await client.deleteTransaction(request: request)

        switch response.result {
        case .success:
            transactions.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that transaction."
        }
    }
}
