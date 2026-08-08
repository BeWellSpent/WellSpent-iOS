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
}
