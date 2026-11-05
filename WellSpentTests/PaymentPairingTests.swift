import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PaymentPairing")
struct PaymentPairingTests {
    private func tx(_ id: String, units: Int64, nanos: Int32 = 0, method: String, day: Int, name: String = "payment") -> Wellspent_V1_Transaction {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = 12
        let date = Calendar.current.date(from: components)!
        return .with {
            $0.id = id
            $0.name = name
            $0.amount = .with { $0.units = units; $0.nanos = nanos; $0.currency = "USD" }
            $0.paymentMethodID = method
            $0.date = Google_Protobuf_Timestamp(dateOnly: date)
        }
    }

    @Test("an outflow and its equal, opposite inflow in another account become one group")
    func pairsMatchingAmounts() {
        let groups = PaymentPairing.group([
            tx("card", units: -532, nanos: -70_000_000, method: "visa", day: 28),
            tx("bank", units: 532, nanos: 70_000_000, method: "checking", day: 29),
        ])

        #expect(groups.count == 1)
        #expect(groups[0].isPair)
        #expect(groups[0].transactions.map(\.id) == ["bank", "card"])
        #expect(groups[0].netAmount.units == 532)
    }

    @Test("the same amount outside the 5 day window stays two rows")
    func windowIsFiveDays() {
        let inside = PaymentPairing.group([
            tx("card", units: -50, method: "visa", day: 1),
            tx("bank", units: 50, method: "checking", day: 6),
        ])
        let outside = PaymentPairing.group([
            tx("card", units: -50, method: "visa", day: 1),
            tx("bank", units: 50, method: "checking", day: 7),
        ])

        #expect(inside.count == 1)
        #expect(outside.count == 2)
    }

    @Test("rows in the same account never pair")
    func sameAccountDoesNotPair() {
        let groups = PaymentPairing.group([
            tx("a", units: -50, method: "checking", day: 1),
            tx("b", units: 50, method: "checking", day: 1),
        ])

        #expect(groups.count == 2)
    }

    @Test("a different amount never pairs, even a cent off")
    func amountMustMatchExactly() {
        let groups = PaymentPairing.group([
            tx("card", units: -50, method: "visa", day: 1),
            tx("bank", units: 50, nanos: 10_000_000, method: "checking", day: 1),
        ])

        #expect(groups.count == 2)
    }

    @Test("two equal payments to two cards pair with the nearest date each, once")
    func eachRowJoinsOnePairOnly() {
        let groups = PaymentPairing.group([
            tx("out1", units: 100, method: "checking", day: 1),
            tx("out2", units: 100, method: "checking", day: 10),
            tx("in1", units: -100, method: "visa", day: 2),
            tx("in2", units: -100, method: "amex", day: 11),
        ])

        #expect(groups.count == 2)
        #expect(Set(groups.map { Set($0.transactions.map(\.id)) }) == [["out1", "in1"], ["out2", "in2"]])
    }

    @Test("'ending in' digits steer a payment to the card whose name carries them")
    func endingDigitsBreakTies() {
        let names = ["chase9967": "Chase ···9967", "chase1324": "Chase ···1324"]
        let groups = PaymentPairing.group([
            tx("out", units: 100, method: "checking", day: 5, name: "Payment to Chase card ending in 9967 10/05"),
            tx("near", units: -100, method: "chase1324", day: 5),
            tx("far", units: -100, method: "chase9967", day: 8),
        ], methodName: { names[$0] })

        let pair = groups.first(where: \.isPair)
        #expect(pair?.transactions.map(\.id) == ["out", "far"])
    }

    @Test("an unmatched row keeps its sign, so a refund subtracts")
    func unmatchedKeepsItsSign() {
        let groups = PaymentPairing.group([tx("lone", units: -65, nanos: -40_000_000, method: "visa", day: 3)])

        #expect(groups.count == 1)
        #expect(!groups[0].isPair)
        #expect(groups[0].netAmount.units == -65)
        #expect(groups[0].netAmount.nanos == -40_000_000)
    }
}
