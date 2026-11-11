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
        #expect(ExpenseOverviewCalculations.isTransactionExcluded(tx))
    }

    @Test("isTransactionExcluded is true for income and card payments, whatever the category")
    func nonSpendFlowsExcluded() {
        var income = transaction(categoryID: 1, amount: -10)
        income.flow = "income"
        var payment = transaction(categoryID: 1, amount: 10)
        payment.flow = "payment"
        #expect(ExpenseOverviewCalculations.isTransactionExcluded(income))
        #expect(ExpenseOverviewCalculations.isTransactionExcluded(payment))
    }

    @Test("isTransactionExcluded is false for a transfer: it counts toward its category")
    func transferCounts() {
        var transfer = transaction(categoryID: 1, amount: -12)
        transfer.flow = "transfer"
        #expect(!ExpenseOverviewCalculations.isTransactionExcluded(transfer))
    }

    @Test("isTransactionExcluded is false otherwise")
    func notExcluded() {
        let tx = transaction(categoryID: 1, amount: 10)
        #expect(!ExpenseOverviewCalculations.isTransactionExcluded(tx))
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
