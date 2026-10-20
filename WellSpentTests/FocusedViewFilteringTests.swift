import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("FocusedViewFiltering")
struct FocusedViewFilteringTests {
    private var methods: [Wellspent_V1_PaymentMethod] {
        [.with { $0.id = "pm-mine"; $0.budgetPersonID = 1 },
         .with { $0.id = "pm-orphan"; $0.budgetPersonID = 0 }]
    }

    @Test("empty payment method id resolves to no owner")
    func emptyIDHasNoOwner() {
        #expect(FocusedViewFiltering.ownerID(paymentMethodID: "", paymentMethods: methods) == nil)
    }

    @Test("an unattributed method resolves to no owner")
    func unattributedMethodHasNoOwner() {
        #expect(FocusedViewFiltering.ownerID(paymentMethodID: "pm-orphan", paymentMethods: methods) == nil)
    }

    @Test("an attributed method resolves to its person")
    func attributedMethodResolvesOwner() {
        #expect(FocusedViewFiltering.ownerID(paymentMethodID: "pm-mine", paymentMethods: methods) == 1)
    }

    @Test("includes a row attributed to the caller")
    func includesMine() {
        #expect(FocusedViewFiltering.isMineOrUnattributed(1, myPersonID: 1))
    }

    @Test("includes an unattributed row regardless of who the caller is")
    func includesUnattributed() {
        #expect(FocusedViewFiltering.isMineOrUnattributed(0, myPersonID: 1))
    }

    @Test("excludes a row attributed to someone else")
    func excludesSomeoneElse() {
        #expect(!FocusedViewFiltering.isMineOrUnattributed(2, myPersonID: 1))
    }

    @Test("excludes everyone when the caller has no resolved person id")
    func excludesWhenCallerUnresolved() {
        #expect(!FocusedViewFiltering.isMineOrUnattributed(2, myPersonID: nil))
    }
}
