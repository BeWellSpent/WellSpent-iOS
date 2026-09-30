import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("CreateFixedFromTransaction")
struct CreateFixedFromTransactionTests {
    func tx(typeID: Int32 = 2, units: Int64 = 1000, planID: String = "") -> Wellspent_V1_Transaction {
        .with {
            $0.transactionTypeID = typeID
            $0.amount = .with { $0.units = units }
            $0.installmentFixedExpenseID = planID
        }
    }

    @Test("only a variable spend can become a fixed expense")
    func canCreateRules() {
        #expect(CreateFixedFromTransaction.canCreate(tx()))
        #expect(!CreateFixedFromTransaction.canCreate(tx(typeID: 1)), "Fixed is already the recurring thing")
        #expect(!CreateFixedFromTransaction.canCreate(tx(planID: "fe-1")), "already an installment plan")
        #expect(!CreateFixedFromTransaction.canCreate(tx(units: -1000)), "a negative amount is money received")
        #expect(!CreateFixedFromTransaction.canCreate(tx(units: 0)))
    }
}
