import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ExpenseOverviewCalculations")
struct ExpenseOverviewCalculationsTests {
    private func transaction(
        categoryID: Int32,
        paymentMethodID: String = "",
        amount: Int64,
        typeID: Int32 = 2,
        isPaid: Bool = false,
        isExcluded: Bool = false
    ) -> Wellspent_V1_Transaction {
        .with {
            $0.categoryID = categoryID
            $0.paymentMethodID = paymentMethodID
            $0.amount = .with { $0.units = amount; $0.currency = "USD" }
            $0.transactionTypeID = typeID
            $0.isPaid = isPaid
            $0.isExcluded = isExcluded
        }
    }

    @Test("isTransactionExcluded is true for manually excluded transactions")
    func manuallyExcluded() {
        let tx = transaction(categoryID: 1, amount: 10, isExcluded: true)
        #expect(ExpenseOverviewCalculations.isTransactionExcluded(tx, incomeCategoryID: nil))
    }

    @Test("isTransactionExcluded is true for the Income category regardless of the flag")
    func incomeCategoryAlwaysExcluded() {
        let tx = transaction(categoryID: 99, amount: 10, isExcluded: false)
        #expect(ExpenseOverviewCalculations.isTransactionExcluded(tx, incomeCategoryID: 99))
    }

    @Test("isTransactionExcluded is false otherwise")
    func notExcluded() {
        let tx = transaction(categoryID: 1, amount: 10)
        #expect(!ExpenseOverviewCalculations.isTransactionExcluded(tx, incomeCategoryID: 99))
    }

    @Test("computeActualTotals skips manually excluded and Income-category transactions")
    func skipsExcludedTransactions() {
        let transactions = [
            transaction(categoryID: 1, amount: 100, isExcluded: true),
            transaction(categoryID: 99, amount: 200),
            transaction(categoryID: 1, amount: 50)
        ]
        let totals = ExpenseOverviewCalculations.computeActualTotals(
            transactions: transactions,
            paymentMethodPersonMap: [:],
            incomeCategoryID: 99
        )
        #expect(totals.byCategory[1]?.units == 50)
        #expect(totals.byCategory[99] == nil)
    }

    @Test("computeActualTotals skips unpaid Fixed-type transactions")
    func skipsUnpaidFixed() {
        let transactions = [
            transaction(categoryID: 1, amount: 100, typeID: 1, isPaid: false),
            transaction(categoryID: 1, amount: 200, typeID: 1, isPaid: true)
        ]
        let totals = ExpenseOverviewCalculations.computeActualTotals(
            transactions: transactions,
            paymentMethodPersonMap: [:],
            incomeCategoryID: nil
        )
        #expect(totals.byCategory[1]?.units == 200)
    }

    @Test("computeActualTotals attributes by payment method to person, defaulting to unattributed")
    func attributesByPerson() {
        let transactions = [
            transaction(categoryID: 1, paymentMethodID: "pm-1", amount: 100),
            transaction(categoryID: 1, paymentMethodID: "pm-unknown", amount: 30)
        ]
        let totals = ExpenseOverviewCalculations.computeActualTotals(
            transactions: transactions,
            paymentMethodPersonMap: ["pm-1": 7],
            incomeCategoryID: nil
        )
        #expect(totals.byCategoryPerson[1]?[7]?.units == 100)
        #expect(totals.byCategoryPerson[1]?[0]?.units == 30)
    }

    @Test("computeActualTotals buckets categoryless transactions as uncategorized")
    func bucketsUncategorized() {
        let transactions = [
            transaction(categoryID: 0, amount: 40),
            transaction(categoryID: 0, amount: 10)
        ]
        let totals = ExpenseOverviewCalculations.computeActualTotals(
            transactions: transactions,
            paymentMethodPersonMap: [:],
            incomeCategoryID: nil
        )
        #expect(totals.uncategorized.units == 50)
        #expect(totals.byCategory.isEmpty)
    }

    @Test("isOver is false when planned is zero or negative")
    func isOverFalseWhenNoPlan() {
        #expect(!ExpenseOverviewCalculations.isOver(actual: (100, 0), planned: (0, 0)))
    }

    @Test("isOver is true only when actual exceeds planned")
    func isOverReflectsComparison() {
        #expect(!ExpenseOverviewCalculations.isOver(actual: (50, 0), planned: (100, 0)))
        #expect(!ExpenseOverviewCalculations.isOver(actual: (100, 0), planned: (100, 0)))
        #expect(ExpenseOverviewCalculations.isOver(actual: (101, 0), planned: (100, 0)))
    }

    @Test("totalOverBudget sums only the overspent portion of planned categories")
    func totalOverBudgetSumsOverspendOnly() {
        // cat 1: over by 20. cat 2: under, contributes 0. cat 3: unplanned, contributes 0 (that's totalUnplanned's job).
        let actual: [Int32: (units: Int64, nanos: Int32)] = [1: (120, 0), 2: (50, 0), 3: (30, 0)]
        let planned: [Int32: (units: Int64, nanos: Int32)] = [1: (100, 0), 2: (100, 0), 3: (0, 0)]
        let result = ExpenseOverviewCalculations.totalOverBudget(
            categoryIDs: [1, 2, 3],
            actual: { actual[$0] ?? (0, 0) },
            planned: { planned[$0] ?? (0, 0) }
        )
        #expect(result.units == 20)
    }

    @Test("totalUnplanned sums uncategorized plus full actual spend in categories with no plan")
    func totalUnplannedSumsUncategorizedAndNoPlanCategories() {
        // cat 1: planned, excluded regardless of over/under. cat 2: unplanned, full actual counts.
        let actual: [Int32: (units: Int64, nanos: Int32)] = [1: (120, 0), 2: (75, 0)]
        let planned: [Int32: (units: Int64, nanos: Int32)] = [1: (100, 0), 2: (0, 0)]
        let result = ExpenseOverviewCalculations.totalUnplanned(
            uncategorized: (25, 0),
            categoryIDs: [1, 2],
            actual: { actual[$0] ?? (0, 0) },
            planned: { planned[$0] ?? (0, 0) }
        )
        #expect(result.units == 100) // 25 uncategorized + 75 from the unplanned category
    }
}
