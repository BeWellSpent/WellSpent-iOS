import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionFlowKind")
struct TransactionFlowKindTests {
    private func tx(flow: String, units: Int64) -> Wellspent_V1_Transaction {
        .with { $0.flow = flow; $0.amount = .with { $0.units = units } }
    }

    @Test("reads the server's flow, falling back to the sign")
    func readsFlow() {
        #expect(TransactionFlowKind.of(tx(flow: "transfer", units: -10)) == .transfer)
        #expect(TransactionFlowKind.of(tx(flow: "", units: -10)) == .refund)
        #expect(TransactionFlowKind.of(tx(flow: "", units: 10)) == .spend)
    }

    @Test("only income and payment are left out of spending")
    func countsAsSpending() {
        #expect(TransactionFlowKind.allCases.filter { !$0.countsAsSpending } == [.income, .payment])
    }

    @Test("chips per direction; payment is kept, never offered")
    func choices() {
        #expect(TransactionFlowKind.choices(moneyIn: false) == [.spend, .transfer])
        #expect(TransactionFlowKind.choices(moneyIn: true) == [.refund, .income, .transfer])
        #expect(TransactionFlowKind.fitting(.payment, moneyIn: true) == .payment)
        #expect(TransactionFlowKind.fitting(.spend, moneyIn: true) == .refund)
    }
}
