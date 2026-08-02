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
    private(set) var allocations: [Wellspent_V1_ExpenseAllocation] = []
    private(set) var savingsSources: [Wellspent_V1_SavingsSource] = []
    private(set) var fixedTransactions: [Wellspent_V1_Transaction] = []
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String

    private let client: Wellspent_V1_BudgetServiceClient

    private var incomeCategoryID: Int32? {
        categories.first { $0.isSystem && $0.name == "Income" }?.id
    }

    /// Mirrors web's `computeOverBudgetTxIds` — for each category, the
    /// planned figure reuses `ExpensePlanCalculations.plannedTotal` (the
    /// same allocations/fixed-fallback rule Plan/Overview already use, with
    /// the same accepted "not-yet-due fixed expense" gap, not a new one).
    var overBudgetTransactionIDs: Set<String> {
        TransactionFiltering.overBudgetTransactionIDs(variableTransactions: transactions) { categoryID in
            guard let category = categories.first(where: { $0.id == categoryID }) else { return (0, 0) }
            let isSavings = ExpensePlanCalculations.isSavingsCategory(category)
            let savingsAmounts = isSavings ? savingsSources.map { (units: $0.amount.units, nanos: $0.amount.nanos) } : []
            let fixedAmounts = fixedTransactions
                .filter { $0.categoryID == categoryID }
                .map { (units: $0.plannedAmount.units, nanos: $0.plannedAmount.nanos) }
            return ExpensePlanCalculations.plannedTotal(
                for: categoryID,
                isSavings: isSavings,
                allocations: allocations,
                savingsAmounts: savingsAmounts,
                fixedPlannedAmounts: fixedAmounts
            )
        }
    }

    /// Sum of every non-excluded transaction's signed amount, formatted.
    /// Uses the same exclusion rule as Expense Overview — manually excluded,
    /// or the system "Income" category, which is always excluded regardless
    /// of the flag.
    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: transactions
                .filter { !ExpenseOverviewCalculations.isTransactionExcluded($0, incomeCategoryID: incomeCategoryID) }
                .map { (units: $0.amount.units, nanos: $0.amount.nanos) },
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
        async let allocationsResponse = client.listExpenseAllocations(request: .with { $0.budgetProfileID = budgetProfileID })
        async let savingsResponse = client.listSavingsSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let fixedTransactionsResponse = client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = FixedExpensesViewModel.fixedTypeID
        })

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
        if case .success(let message) = await allocationsResponse.result {
            allocations = message.allocations
        }
        if case .success(let message) = await savingsResponse.result {
            savingsSources = message.sources
        }
        if case .success(let message) = await fixedTransactionsResponse.result {
            fixedTransactions = message.transactions
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

    func categoryName(for categoryID: Int32) -> String? {
        guard categoryID != 0 else { return nil }
        return categories.first(where: { $0.id == categoryID })?.name
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
