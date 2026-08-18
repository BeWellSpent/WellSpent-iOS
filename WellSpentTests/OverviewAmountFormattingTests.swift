import Testing
@testable import WellSpent

@Suite("OverviewAmountFormatting")
struct OverviewAmountFormattingTests {
    private func text(_ units: Int64, _ nanos: Int32 = 0) -> String {
        OverviewAmountFormatting.text(
            (units: units, nanos: nanos),
            currencyCode: "USD",
            localeIdentifier: "en_US"
        )
    }

    @Test("spending reads as a positive magnitude, unlike the Transactions tab")
    func spendingIsUnsigned() {
        #expect(text(420) == "$420.00")
    }

    @Test("money received reads +$X, matching the Transactions tab")
    func receivedIsPrefixed() {
        #expect(text(-85) == "+$85.00")
    }

    // The whole point of the change: a refund used to render "-$85.00" here
    // and "+$85.00" on the Transactions tab, so the sign read as inverted
    // between the two.
    @Test("a received amount is never rendered with a minus sign")
    func receivedIsNeverNegative() {
        #expect(!text(-85).contains("-"))
    }

    // units is 0 but nanos is negative — a sub-unit refund. A units-only sign
    // check would call this a spend and print "-$0.50".
    @Test("a sub-unit received amount is still treated as received")
    func subUnitReceived() {
        #expect(text(0, -500_000_000) == "+$0.50")
    }

    @Test("zero renders as an ordinary zero, not a signed one")
    func zeroIsUnsigned() {
        #expect(text(0) == "$0.00")
    }

    private func tone(
        actual: Int64,
        planned: Int64,
        isOver: Bool = false
    ) -> OverviewAmountFormatting.Tone {
        OverviewAmountFormatting.tone(
            actual: (units: actual, nanos: 0),
            planned: (units: planned, nanos: 0),
            isOver: isOver
        )
    }

    @Test("a spend inside its plan is withinPlan")
    func withinPlan() {
        #expect(tone(actual: 300, planned: 400) == .withinPlan)
    }

    @Test("a spend over its plan is over")
    func over() {
        #expect(tone(actual: 500, planned: 400, isOver: true) == .over)
    }

    // The reason tone takes `planned` at all. isOver is
    // `planned > 0 && actual > planned` server-side, so unplanned spending can
    // never be "over" and used to fall through to the same styling as a spend
    // that was inside its plan — reading as within budget while the same money
    // was counted into the orange Unplanned total on the same screen.
    @Test("spending with no plan is unplanned, not withinPlan")
    func unplanned() {
        #expect(tone(actual: 500, planned: 0) == .unplanned)
    }

    @Test("money received is received, never over")
    func receivedTone() {
        #expect(tone(actual: -85, planned: 0) == .received)
        #expect(tone(actual: -85, planned: 40, isOver: true) == .received)
    }

    @Test("an exactly-zero actual is zero, even against a real plan")
    func zeroTone() {
        #expect(tone(actual: 0, planned: 400) == .zero)
    }
}
