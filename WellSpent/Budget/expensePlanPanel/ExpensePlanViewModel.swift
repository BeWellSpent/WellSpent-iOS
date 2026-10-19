import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class ExpensePlanViewModel {
    private(set) var isLoading = false
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var allocations: [Wellspent_V1_ExpenseAllocation] = []
    /// Server-computed planned/committed/remainder totals and category
    /// visibility/sort order — the single source of truth both this client
    /// and WellSpent-web consume (see docs/features/expense-summary.md,
    /// issue #35), replacing what used to be a hand-ported copy of web's
    /// planned-total fallback chain (allocation -> due Fixed -> not-due
    /// Fixed template) computed from raw savings/income/fixed-transaction
    /// data fetched here.
    private(set) var summary: Wellspent_V1_GetExpenseSummaryResponse?
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

    var visibleCategories: [Wellspent_V1_Category] {
        (summary?.planCategories ?? []).compactMap { summary in
            categories.first { $0.id == summary.categoryID }
        }
    }

    var incomeTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.incomeFromSources)
    }

    var committedTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.totalCommitted)
    }

    var remainderTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.tuple(from: summary?.remainderPlan)
    }

    /// Chart data for the planned-amount chart. Mirrors web's chart-data
    /// construction in `ExpensesPanel.tsx` (category-grouping mode).
    var chartData: [ExpenseChartCalculations.Datum] {
        ExpenseChartCalculations.data(categories: visibleCategories, amount: { [self] in plannedTotal(for: $0) })
    }

    func plannedTotal(for category: Wellspent_V1_Category) -> (units: Int64, nanos: Int32) {
        guard let row = planRow(for: category) else { return (0, 0) }
        return TransactionAmountFormatting.tuple(from: row.plannedTotal)
    }

    /// Fixed expenses templated for this category but not due in this period.
    /// Shown as a muted caption and counted toward nothing — see
    /// `ExpensePlanCalculations.categoryTotal` (issue #48).
    func notDuePlannedTotal(for category: Wellspent_V1_Category) -> (units: Int64, nanos: Int32) {
        guard let row = planRow(for: category), row.hasNotDuePlannedTotal else { return (0, 0) }
        return TransactionAmountFormatting.tuple(from: row.notDuePlannedTotal)
    }

    /// When this category next costs anything, for the not-due caption.
    /// Empty when nothing is upcoming.
    func nextDueText(for category: Wellspent_V1_Category) -> String {
        guard let row = planRow(for: category), row.hasNextDueDate else { return "" }
        return NextDueDateFormatting.text(row.nextDueDate, localeIdentifier: localeIdentifier)
    }

    private func planRow(for category: Wellspent_V1_Category) -> Wellspent_V1_CategoryExpenseSummary? {
        summary?.planCategories.first { $0.categoryID == category.id }
    }

    func allocations(for categoryID: Int32) -> [Wellspent_V1_ExpenseAllocation] {
        allocations.filter { $0.categoryID == categoryID }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let allocationsResult = fetchAllocations()
        async let categoriesResult = fetchCategories()
        async let peopleResult = fetchPeople()

        if let fetched = await allocationsResult {
            allocations = fetched
        }

        if let fetched = await categoriesResult {
            categories = fetched
        }
        if let fetched = await peopleResult {
            people = fetched
        }

        // Needs `people` resolved first, so this can't join the batch above.
        let focusedView = ChartPreference.myPerson(currentUserID: currentUserID, people: people)?.focusedViewEnabled ?? false
        if let fetched = await fetchSummary(focusedView: focusedView) {
            summary = fetched
        }
    }

    private func fetchAllocations() async -> [Wellspent_V1_ExpenseAllocation]? {
        do {
            let output = try await restClient.listExpenseAllocations(.init(path: .init(id: budgetProfileID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load the expense plan."
                return nil
            }
            return body.allocations.map(BudgetRESTMapping.expenseAllocation(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load the expense plan."
            return nil
        }
    }

    private func fetchSummary(focusedView: Bool) async -> Wellspent_V1_GetExpenseSummaryResponse? {
        do {
            let output = try await restClient.getExpenseSummary(.init(path: .init(id: budgetPeriodID), query: .init(focusedView: focusedView)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                if errorMessage == nil { errorMessage = "Couldn't load the expense summary." }
                return nil
            }
            return BudgetRESTMapping.expenseSummary(from: body)
        } catch {
            if errorMessage == nil { errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load the expense summary." }
            return nil
        }
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

    /// Applies the allocate sheet's diff: upserts changed/nonblank rows,
    /// deletes rows the user cleared. Runs sequentially (small counts, one
    /// category at a time) then reloads so `visibleCategories`/totals reflect
    /// the change.
    func applyAllocationChanges(
        upserted: [(budgetPersonID: Int64, categoryID: Int32, plannedAmount: Wellspent_V1_Money)],
        deletedIDs: [Int64]
    ) async {
        errorMessage = nil

        for change in upserted {
            do {
                guard case .ok = try await restClient.upsertExpenseAllocation(.init(
                    path: .init(id: budgetProfileID),
                    body: .json(.init(
                        categoryId: change.categoryID,
                        budgetPersonId: change.budgetPersonID == 0 ? nil : change.budgetPersonID,
                        plannedAmount: BudgetRESTMapping.restMoney(from: change.plannedAmount)
                    ))
                )) else {
                    errorMessage = "Couldn't save that allocation."
                    continue
                }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't save that allocation."
            }
        }

        for id in deletedIDs {
            do {
                // allocationId is declared int32 in the contract despite ExpenseAllocation.id being
                // int64 (SERIAL bigint) everywhere else — a minor, non-blocking contract inconsistency,
                // unlike the RecurringFrequency gap; truncating avoids a crash on the (never-reached-in-
                // practice) case where this table's row count exceeds Int32.max.
                guard case .ok = try await restClient.deleteExpenseAllocation(.init(path: .init(id: budgetProfileID, allocationId: Int32(truncatingIfNeeded: id)))) else {
                    errorMessage = "Couldn't remove that allocation."
                    continue
                }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't remove that allocation."
            }
        }

        await load()
    }
}
