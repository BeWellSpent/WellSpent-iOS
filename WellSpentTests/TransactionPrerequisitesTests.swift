import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionPrerequisites")
struct TransactionPrerequisitesTests {
    private func method(_ id: String = "pm-1") -> Wellspent_V1_PaymentMethod {
        .with { $0.id = id }
    }

    @Test("blocks when the budget has no payment methods")
    func blocksWithNoPaymentMethods() {
        #expect(TransactionPrerequisites.needsPaymentMethod(paymentMethods: [], isLoading: false))
    }

    @Test("allows once at least one payment method exists")
    func allowsWithOnePaymentMethod() {
        #expect(!TransactionPrerequisites.needsPaymentMethod(paymentMethods: [method()], isLoading: false))
    }

    @Test("does not block while the list is still loading")
    func doesNotBlockWhileLoading() {
        #expect(!TransactionPrerequisites.needsPaymentMethod(paymentMethods: [], isLoading: true))
    }
}
