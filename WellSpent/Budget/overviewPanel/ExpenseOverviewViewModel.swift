import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

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
    /// Per-person period figures and the plan's "not planned yet" — REST-only,
    /// so carried beside `summary` rather than inside the generated type.
    private(set) var personSummaries: [BudgetRESTMapping.PersonPeriodSummary] = []
    private(set) var unattributedSpent: Wellspent_V1_Money?
    private(set) var remainderPlanIncludingSavings: Wellspent_V1_Money?
    /// Set while the Chart style menu's choice is being saved; overrides the stored one meanwhile.
    private(set) var chartTypeOverride: ExpenseChartView.ChartType?
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let currentUserID: String?

    private let restClient: WellSpentREST.Client

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, currentUserID: String?, restClient: WellSpentREST.Client) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.currentUserID = currentUserID
        self.restClient = restClient
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

    // MARK: Plan card

    var plannedIncome: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.incomeFromSources)
    }

    var plannedExpensesIncludingSavings: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalCommittedIncludingSavings)
    }

    var plannedExpenses: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalCommitted)
    }

    /// Nil from a server that predates it, so the row hides rather than reading $0.
    var remainingPlan: (units: Int64, nanos: Int32)? {
        remainderPlanIncludingSavings.map { TransactionAmountFormatting.tuple(from: $0) }
    }

    // MARK: People

    /// Person cards in the budget's own order. Under focused view the server
    /// sends only the caller, so only that card shows.
    var personCards: [(person: Wellspent_V1_BudgetPerson, summary: BudgetRESTMapping.PersonPeriodSummary)] {
        personSummaries.compactMap { summary in
            people.first { $0.id == summary.budgetPersonID }.map { (person: $0, summary: summary) }
        }
    }

    var unattributedSpentAmount: (units: Int64, nanos: Int32)? {
        guard let unattributedSpent else { return nil }
        let amount = TransactionAmountFormatting.tuple(from: unattributedSpent)
        return HomeOverviewCalculations.isZero(amount) ? nil : amount
    }

    // MARK: Categories

    var categoriesSpent: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalActualIncludingSavings)
    }

    var categoriesPlanned: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalPlannedIncludingSavings)
    }

    var overCategories: [Wellspent_V1_Category] {
        visibleCategories.filter { isOver(for: $0) }
    }

    func chartSegments(otherName: String) -> [HomeOverviewCalculations.Segment] {
        HomeOverviewCalculations.segments(
            visibleCategories.map { .init(id: String($0.id), name: $0.displayName, colorHex: $0.color, amount: actualTotal(for: $0)) },
            otherName: otherName
        )
    }

    /// The person's saved Overview chart preference, or the shared default.
    var chartType: ExpenseChartView.ChartType {
        if let chartTypeOverride { return chartTypeOverride }
        let me = ChartPreference.myPerson(currentUserID: currentUserID, people: people)
        return ChartPreference.chartType(for: me?.overviewChartType ?? .unspecified)
    }

    /// Saves the Chart style menu's choice as the person's Overview
    /// preference, the same one Preferences sets, keeping their Plan
    /// preference as it is. Shown at once and rolled back if the save fails.
    func setChartType(_ type: ExpenseChartView.ChartType) async {
        let previous = chartType
        chartTypeOverride = type
        let me = ChartPreference.myPerson(currentUserID: currentUserID, people: people)
        let plan = me?.planChartType ?? .unspecified
        do {
            let output = try await restClient.updateMyBudgetPreferences(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(
                    planChartType: BudgetRESTMapping.restChartType(from: plan),
                    overviewChartType: BudgetRESTMapping.restChartType(from: ChartPreference.stored(for: type))
                ))
            ))
            guard case .ok = output else {
                RESTNetworkError.logUnexpectedOutput(output)
                chartTypeOverride = previous
                return
            }
            if let fetched = await fetchPeople() {
                people = fetched
                chartTypeOverride = nil
            }
        } catch {
            _ = RESTNetworkError.connectivityMessage(for: error)
            chartTypeOverride = previous
        }
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
                && !($0.transactionTypeID == TransactionsViewModel.fixedTypeID && !$0.isPaid)
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

        async let categoriesResult = fetchCategories()
        async let peopleResult = fetchPeople()
        async let paymentMethodsResult = fetchPaymentMethods()

        if let fetched = await categoriesResult {
            categories = fetched
        }
        if let fetched = await peopleResult {
            people = fetched
        }
        if let fetched = await paymentMethodsResult {
            paymentMethods = fetched
        }

        // Needs `people` resolved first, so these can't join the batch above.
        let focusedView = ChartPreference.myPerson(currentUserID: currentUserID, people: people)?.focusedViewEnabled ?? false
        async let transactionsResult = fetchTransactions(focusedView: focusedView)
        async let summaryResult = fetchSummary(focusedView: focusedView)

        if let fetched = await transactionsResult {
            transactions = fetched
        }

        if let fetched = await summaryResult {
            summary = fetched.summary
            personSummaries = fetched.people
            unattributedSpent = fetched.unattributed
            remainderPlanIncludingSavings = fetched.remainderPlan
        } else if errorMessage == nil {
            errorMessage = "Couldn't load the expense summary."
        }
    }

    private func fetchSummary(focusedView: Bool) async -> (
        summary: Wellspent_V1_GetExpenseSummaryResponse,
        people: [BudgetRESTMapping.PersonPeriodSummary],
        unattributed: Wellspent_V1_Money?,
        remainderPlan: Wellspent_V1_Money?
    )? {
        guard let output = try? await restClient.getExpenseSummary(.init(path: .init(id: budgetPeriodID), query: .init(focusedView: focusedView))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return (
            BudgetRESTMapping.expenseSummary(from: body),
            BudgetRESTMapping.personPeriodSummaries(from: body),
            BudgetRESTMapping.unattributedSpent(from: body),
            BudgetRESTMapping.remainderPlanIncludingSavings(from: body)
        )
    }

    private func fetchCategories() async -> [Wellspent_V1_Category]? {
        guard let output = try? await restClient.listCategories(.init(query: .init(budgetProfileId: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.categories.map(BudgetRESTMapping.category(from:))
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.people.map(BudgetRESTMapping.person(from:))
    }

    private func fetchPaymentMethods() async -> [Wellspent_V1_PaymentMethod]? {
        guard let output = try? await restClient.listPaymentMethods(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.methods.map(BudgetRESTMapping.paymentMethod(from:))
    }

    private func fetchTransactions(focusedView: Bool) async -> [Wellspent_V1_Transaction]? {
        do {
            let output = try await restClient.listTransactions(.init(query: .init(budgetPeriodId: budgetPeriodID, focusedView: focusedView)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load the expense overview."
                return nil
            }
            return body.transactions.map(BudgetRESTMapping.transaction(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load the expense overview."
            return nil
        }
    }
}
