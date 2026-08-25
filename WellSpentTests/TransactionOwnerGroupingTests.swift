import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionOwnerGrouping")
struct TransactionOwnerGroupingTests {
    private func transaction(_ id: String, paymentMethodID: String, day: Int = 1) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.paymentMethodID = paymentMethodID
            $0.date = Google_Protobuf_Timestamp(dateOnly: DateComponents(
                calendar: .current, year: 2026, month: 6, day: day
            ).date ?? Date())
        }
    }

    private func method(_ id: String, personID: Int64) -> Wellspent_V1_PaymentMethod {
        .with { $0.id = id; $0.budgetPersonID = personID }
    }

    private var methods: [Wellspent_V1_PaymentMethod] {
        [method("pm-alex", personID: 1), method("pm-sam", personID: 2), method("pm-orphan", personID: 0)]
    }

    @Test("a transaction belongs to the person its payment method belongs to")
    func resolvesOwner() {
        #expect(TransactionOwnerGrouping.ownerID(
            of: transaction("t1", paymentMethodID: "pm-alex"), paymentMethods: methods
        ) == 1)
    }

    // The server credits a person only when the transaction has a payment
    // method AND that method names one. These three must fall out, or a
    // person's listed transactions stop matching their own total.
    @Test("spending with no method, an unattributed method, or an unknown method belongs to nobody")
    func resolvesNoOwner() {
        #expect(TransactionOwnerGrouping.ownerID(
            of: transaction("t1", paymentMethodID: ""), paymentMethods: methods) == nil)
        #expect(TransactionOwnerGrouping.ownerID(
            of: transaction("t2", paymentMethodID: "pm-orphan"), paymentMethods: methods) == nil)
        #expect(TransactionOwnerGrouping.ownerID(
            of: transaction("t3", paymentMethodID: "pm-deleted"), paymentMethods: methods) == nil)
    }

    @Test("files each transaction under the person who paid")
    func groupsByPayer() {
        let groups = TransactionOwnerGrouping.group(
            [transaction("a", paymentMethodID: "pm-alex"),
             transaction("b", paymentMethodID: "pm-sam"),
             transaction("c", paymentMethodID: "pm-alex")],
            paymentMethods: methods,
            renderedPersonIDs: [1, 2]
        )
        #expect(Set((groups.byPerson[1] ?? []).map(\.id)) == ["a", "c"])
        #expect((groups.byPerson[2] ?? []).map(\.id) == ["b"])
        #expect(groups.unclaimed.isEmpty)
    }

    @Test("spending that belongs to nobody gets its own group")
    func unattributedIsSeparate() {
        let groups = TransactionOwnerGrouping.group(
            [transaction("cash", paymentMethodID: ""), transaction("a", paymentMethodID: "pm-alex")],
            paymentMethods: methods,
            renderedPersonIDs: [1, 2]
        )
        #expect(groups.unclaimed.map(\.id) == ["cash"])
        #expect((groups.byPerson[1] ?? []).map(\.id) == ["a"])
    }

    @Test("a transaction owned by someone with no row is still listed")
    func ownerWithoutRowIsNotDropped() {
        let groups = TransactionOwnerGrouping.group(
            [transaction("a", paymentMethodID: "pm-sam")],
            paymentMethods: methods,
            renderedPersonIDs: [1]
        )
        #expect(groups.unclaimed.map(\.id) == ["a"])
    }

    @Test("no transaction is ever lost, whatever its attribution")
    func neverLosesATransaction() {
        let all = [
            transaction("a", paymentMethodID: "pm-alex"),
            transaction("b", paymentMethodID: "pm-sam"),
            transaction("cash", paymentMethodID: ""),
            transaction("orphan", paymentMethodID: "pm-orphan")
        ]
        let groups = TransactionOwnerGrouping.group(all, paymentMethods: methods, renderedPersonIDs: [1, 2])
        let seen = Set(groups.byPerson.values.flatMap { $0 }.map(\.id)).union(groups.unclaimed.map(\.id))
        #expect(seen == ["a", "b", "cash", "orphan"])
    }

    @Test("each group runs newest first")
    func ordersNewestFirst() {
        let groups = TransactionOwnerGrouping.group(
            [transaction("old", paymentMethodID: "pm-alex", day: 1),
             transaction("new", paymentMethodID: "pm-alex", day: 20),
             transaction("mid", paymentMethodID: "pm-alex", day: 10)],
            paymentMethods: methods,
            renderedPersonIDs: [1]
        )
        #expect((groups.byPerson[1] ?? []).map(\.id) == ["new", "mid", "old"])
    }

    @Test("a same-day tie breaks on ID, so the order is stable between renders")
    func stableWithinADay() {
        let groups = TransactionOwnerGrouping.group(
            [transaction("b", paymentMethodID: "pm-alex", day: 5),
             transaction("a", paymentMethodID: "pm-alex", day: 5)],
            paymentMethods: methods,
            renderedPersonIDs: [1]
        )
        #expect((groups.byPerson[1] ?? []).map(\.id) == ["a", "b"])
    }
}
