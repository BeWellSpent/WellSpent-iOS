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
    private(set) var savingsSources: [Wellspent_V1_SavingsSource] = []
    private(set) var incomeSources: [Wellspent_V1_IncomeSource] = []
    private(set) var fixedTransactions: [Wellspent_V1_Transaction] = []
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
        ExpensePlanCalculations.sortedVisibleCategories(categories: categories) { [self] category in
            plannedTotal(for: category)
        }
    }

    var incomeTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.sum(incomeSources.map { (units: $0.defaultAmount.units, nanos: $0.defaultAmount.nanos) })
    }

    var committedTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.sum(visibleCategories.map { plannedTotal(for: $0) })
    }

    var remainderTotal: (units: Int64, nanos: Int32) {
        let income = incomeTotal
        let committed = committedTotal
        return TransactionAmountFormatting.sum([
            (units: income.units, nanos: income.nanos),
            (units: -committed.units, nanos: -committed.nanos)
        ])
    }

    /// Chart data for the planned-amount chart. Mirrors web's chart-data
    /// construction in `ExpensesPanel.tsx` (category-grouping mode).
    var chartData: [ExpenseChartCalculations.Datum] {
        ExpenseChartCalculations.data(categories: visibleCategories, amount: { [self] in plannedTotal(for: $0) })
    }

    func plannedTotal(for category: Wellspent_V1_Category) -> (units: Int64, nanos: Int32) {
        let isSavings = ExpensePlanCalculations.isSavingsCategory(category)
        let savingsAmounts = isSavings ? savingsSources.map { (units: $0.amount.units, nanos: $0.amount.nanos) } : []
        let fixedAmounts = fixedTransactions
            .filter { $0.categoryID == category.id }
            .map { (units: $0.plannedAmount.units, nanos: $0.plannedAmount.nanos) }

        return ExpensePlanCalculations.plannedTotal(
            for: category.id,
            isSavings: isSavings,
            allocations: allocations,
            savingsAmounts: savingsAmounts,
            fixedPlannedAmounts: fixedAmounts
        )
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
        async let savingsResponse = client.listSavingsSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let incomeResponse = client.listIncomeSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let transactionsResponse = client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = FixedExpensesViewModel.fixedTypeID
        })

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
        if case .success(let message) = await savingsResponse.result {
            savingsSources = message.sources
        }
        if case .success(let message) = await incomeResponse.result {
            incomeSources = message.sources
        }
        if case .success(let message) = await transactionsResponse.result {
            fixedTransactions = message.transactions
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
