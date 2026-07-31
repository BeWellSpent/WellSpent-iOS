import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class ExpenseOverviewViewModel {
    private(set) var isLoading = false
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var allocations: [Wellspent_V1_ExpenseAllocation] = []
    private(set) var savingsSources: [Wellspent_V1_SavingsSource] = []
    private(set) var incomeEntries: [Wellspent_V1_IncomeEntry] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var transactions: [Wellspent_V1_Transaction] = []
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
        categories.first { $0.isSystem && $0.name == "Income" }?.id
    }

    private var paymentMethodPersonMap: [String: Int64] {
        Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0.budgetPersonID) })
    }

    private var fixedTransactions: [Wellspent_V1_Transaction] {
        transactions.filter { $0.transactionTypeID == FixedExpensesViewModel.fixedTypeID }
    }

    private var actualTotals: ExpenseOverviewCalculations.ActualTotals {
        ExpenseOverviewCalculations.computeActualTotals(
            transactions: transactions,
            paymentMethodPersonMap: paymentMethodPersonMap,
            incomeCategoryID: incomeCategoryID
        )
    }

    var visibleCategories: [Wellspent_V1_Category] {
        ExpensePlanCalculations.sortedVisibleCategories(categories: categories) { [self] category in
            actualTotal(for: category)
        }
    }

    var uncategorizedTotal: (units: Int64, nanos: Int32) {
        actualTotals.uncategorized
    }

    var incomeTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.sum(incomeEntries.map { (units: $0.amount.units, nanos: $0.amount.nanos) })
    }

    var totalActual: (units: Int64, nanos: Int32) {
        let categoryTotals = actualTotals.byCategory.values.map { $0 }
        return TransactionAmountFormatting.sum(categoryTotals + [uncategorizedTotal])
    }

    var remainderTotal: (units: Int64, nanos: Int32) {
        let income = incomeTotal
        let actual = totalActual
        return TransactionAmountFormatting.sum([
            (units: income.units, nanos: income.nanos),
            (units: -actual.units, nanos: -actual.nanos)
        ])
    }

    func actualTotal(for category: Wellspent_V1_Category) -> (units: Int64, nanos: Int32) {
        actualTotals.byCategory[category.id] ?? (0, 0)
    }

    func actualTotal(for category: Wellspent_V1_Category, person: Wellspent_V1_BudgetPerson) -> (units: Int64, nanos: Int32) {
        actualTotals.byCategoryPerson[category.id]?[person.id] ?? (0, 0)
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

    func plannedTotal(for category: Wellspent_V1_Category, person: Wellspent_V1_BudgetPerson) -> (units: Int64, nanos: Int32) {
        let isSavings = ExpensePlanCalculations.isSavingsCategory(category)
        let personAllocations = allocations.filter { $0.categoryID == category.id && $0.budgetPersonID == person.id }
        let personSavingsAmounts = isSavings
            ? savingsSources.filter { $0.budgetPersonID == person.id }.map { (units: $0.amount.units, nanos: $0.amount.nanos) }
            : []
        let personFixedAmounts = fixedTransactions
            .filter { $0.categoryID == category.id && (paymentMethodPersonMap[$0.paymentMethodID] ?? 0) == person.id }
            .map { (units: $0.plannedAmount.units, nanos: $0.plannedAmount.nanos) }

        return ExpensePlanCalculations.plannedTotal(
            for: category.id,
            isSavings: isSavings,
            allocations: personAllocations,
            savingsAmounts: personSavingsAmounts,
            fixedPlannedAmounts: personFixedAmounts
        )
    }

    func isOver(for category: Wellspent_V1_Category) -> Bool {
        ExpenseOverviewCalculations.isOver(actual: actualTotal(for: category), planned: plannedTotal(for: category))
    }

    func isOver(for category: Wellspent_V1_Category, person: Wellspent_V1_BudgetPerson) -> Bool {
        ExpenseOverviewCalculations.isOver(actual: actualTotal(for: category, person: person), planned: plannedTotal(for: category, person: person))
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let categoriesResponse = client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let allocationsResponse = client.listExpenseAllocations(request: .with { $0.budgetProfileID = budgetProfileID })
        async let savingsResponse = client.listSavingsSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })
        async let incomeEntriesResponse = client.listIncomeEntries(request: .with { $0.budgetPeriodID = budgetPeriodID })
        async let transactionsResponse = client.listTransactions(request: .with { $0.budgetPeriodID = budgetPeriodID })

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
        if case .success(let message) = await allocationsResponse.result {
            allocations = message.allocations
        }
        if case .success(let message) = await savingsResponse.result {
            savingsSources = message.sources
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
        if case .success(let message) = await incomeEntriesResponse.result {
            incomeEntries = message.entries
        }
    }
}
