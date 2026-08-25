import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class ExpenseOverviewViewModel {
    private(set) var isLoading = false
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var transactions: [Wellspent_V1_Transaction] = []
    /// Needed only to attribute a transaction to a person — a transaction
    /// names a payment method, and the method names the person. Without this
    /// the drill-down cannot say who spent what (issue #62).
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    /// Server-computed planned/actual/remainder/over-budget/unplanned totals
    /// and category visibility/sort order — the single source of truth both
    /// this client and WellSpent-web consume (see
    /// docs/features/expense-summary.md, issue #35). This view model used to
    /// hand-port web's category-visibility filter and drifted: it only
    /// considered actual spend, silently dropping planned-but-unspent
    /// categories from `visibleCategories`/every total derived from it.
    private(set) var summary: Wellspent_V1_GetExpenseSummaryResponse?
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String

    private let client: Wellspent_V1_BudgetServiceClient

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, authenticatedClient: ProtocolClient) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    private var incomeCategoryID: Int32? {
        categories.first { $0.isSystem(.income) }?.id
    }

    // Already visible-filtered (actual spend OR has a plan) and sorted by
    // actual descending, server-side.
    var visibleCategories: [Wellspent_V1_Category] {
        (summary?.overviewCategories ?? []).compactMap { summary in
            categories.first { $0.id == summary.categoryID }
        }
    }

    private func categorySummary(for categoryID: Int32) -> Wellspent_V1_CategoryExpenseSummary? {
        summary?.overviewCategories.first { $0.categoryID == categoryID }
    }

    var uncategorizedTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.uncategorizedActual)
    }

    var incomeTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.incomeFromEntries)
    }

    var totalActual: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalActual)
    }

    var remainderTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.remainderActual)
    }

    /// Mirrors web's `totalPlanned` in `ExpenseOverviewPanel.tsx`, shown
    /// alongside `totalActual` for comparison.
    var totalPlanned: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalPlanned)
    }

    /// Income minus `totalPlanned` — the planned-side counterpart to
    /// `remainderTotal` (which is income minus *actual*).
    var plannedRemainderTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.remainderPlanned)
    }

    /// Mirrors web's `totalOverBudget`.
    var totalOverBudgetAmount: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalOverBudget)
    }

    /// Mirrors web's `totalUnplanned`.
    var totalUnplannedAmount: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalUnplanned)
    }

    func actualTotal(for category: Wellspent_V1_Category) -> (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: categorySummary(for: category.id)?.actualTotal)
    }

    func actualTotal(for category: Wellspent_V1_Category, person: Wellspent_V1_BudgetPerson) -> (units: Int64, nanos: Int32) {
        let breakdown = categorySummary(for: category.id)?.personBreakdowns.first { $0.budgetPersonID == person.id }
        return TransactionAmountFormatting.tuple(from: breakdown?.actualTotal)
    }

    func plannedTotal(for category: Wellspent_V1_Category) -> (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: categorySummary(for: category.id)?.plannedTotal)
    }

    func plannedTotal(for category: Wellspent_V1_Category, person: Wellspent_V1_BudgetPerson) -> (units: Int64, nanos: Int32) {
        let breakdown = categorySummary(for: category.id)?.personBreakdowns.first { $0.budgetPersonID == person.id }
        return TransactionAmountFormatting.tuple(from: breakdown?.plannedTotal)
    }

    /// Transactions actually counted toward this category's actual total —
    /// same filter the backend's actual-total computation applies (excludes
    /// manually/Income excluded and unpaid Fixed transactions) — for the
    /// expandable per-category transaction list. Mirrors web's
    /// `transactionsByCatId`. This is raw display data (which real
    /// transactions make up the total), not a calculation the total itself
    /// depends on, so it stays derived from the period's transaction list
    /// rather than the summary RPC.
    func transactions(for category: Wellspent_V1_Category) -> [Wellspent_V1_Transaction] {
        transactions.filter {
            $0.categoryID == category.id
                && !ExpenseOverviewCalculations.isTransactionExcluded($0, incomeCategoryID: incomeCategoryID)
                && !($0.transactionTypeID == FixedExpensesViewModel.fixedTypeID && !$0.isPaid)
        }
    }

    /// This category's transactions split by who paid, so each person's
    /// spending can sit under their own row (issue #62).
    ///
    /// Keyed on `people`, not on the summary's `personBreakdowns`, because this
    /// view draws a row for **every** person on the budget — web draws only the
    /// ones with a plan or spend. A pre-existing difference, left alone here;
    /// what matters is that the key matches whatever this client actually puts
    /// on screen, so nothing is filed under a name that isn't there. A
    /// consequence is that `unclaimed` on iOS is purely unattributed spending,
    /// where on web it can also hold a person the server omitted.
    func transactionGroups(for category: Wellspent_V1_Category) -> TransactionOwnerGrouping.Groups {
        let renderedPersonIDs = Set(people.map(\.id))
        return TransactionOwnerGrouping.group(
            transactions(for: category),
            paymentMethods: paymentMethods,
            renderedPersonIDs: renderedPersonIDs
        )
    }

    /// Chart data for the actual-spend chart — colored red for overspent
    /// categories, category color otherwise. Mirrors web's chart-data
    /// construction in `ExpenseOverviewPanel.tsx`.
    var chartData: [ExpenseChartCalculations.Datum] {
        ExpenseChartCalculations.data(
            categories: visibleCategories,
            amount: { [self] in actualTotal(for: $0) },
            colorOverride: { [self] in isOver(for: $0) ? "#ef4444" : nil }
        )
    }

    func isOver(for category: Wellspent_V1_Category) -> Bool {
        categorySummary(for: category.id)?.isOver ?? false
    }

    func isOver(for category: Wellspent_V1_Category, person: Wellspent_V1_BudgetPerson) -> Bool {
        ExpenseOverviewCalculations.isOver(
            actual: actualTotal(for: category, person: person),
            planned: plannedTotal(for: category, person: person)
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let categoriesResponse = client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let transactionsResponse = client.listTransactions(request: .with { $0.budgetPeriodID = budgetPeriodID })
        async let summaryResponse = client.getExpenseSummary(request: .with { $0.budgetPeriodID = budgetPeriodID })
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await transactionsResponse.result {
        case .success(let message):
            transactions = message.transactions
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load the expense overview."
        }

        if case .success(let message) = await categoriesResponse.result {
            categories = message.categories
        }
        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
        switch await summaryResponse.result {
        case .success(let message):
            summary = message
        case .failure(let error):
            if errorMessage == nil {
                errorMessage = error.message ?? "Couldn't load the expense summary."
            }
        }
    }
}
