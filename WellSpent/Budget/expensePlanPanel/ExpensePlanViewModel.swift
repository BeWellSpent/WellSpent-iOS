import Foundation
import Observation
import WellSpentAPI

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

    private let client: Wellspent_V1_BudgetServiceClient

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, authenticatedClient: ProtocolClient) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
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

        async let allocationsResponse = client.listExpenseAllocations(request: .with { $0.budgetProfileID = budgetProfileID })
        async let categoriesResponse = client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let summaryResponse = client.getExpenseSummary(request: .with { $0.budgetPeriodID = budgetPeriodID })

        switch await allocationsResponse.result {
        case .success(let message):
            allocations = message.allocations
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load the expense plan."
        }

        if case .success(let message) = await categoriesResponse.result {
            categories = message.categories
        }
        if case .success(let message) = await peopleResponse.result {
            people = message.people
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
            let response = await client.upsertExpenseAllocation(request: .with {
                $0.budgetProfileID = budgetProfileID
                $0.categoryID = change.categoryID
                $0.budgetPersonID = change.budgetPersonID
                $0.plannedAmount = change.plannedAmount
            })
            if case .failure(let error) = response.result {
                errorMessage = error.message ?? "Couldn't save that allocation."
            }
        }

        for id in deletedIDs {
            let response = await client.deleteExpenseAllocation(request: .with {
                $0.id = id
                $0.budgetProfileID = budgetProfileID
            })
            if case .failure(let error) = response.result {
                errorMessage = error.message ?? "Couldn't remove that allocation."
            }
        }

        await load()
    }
}
