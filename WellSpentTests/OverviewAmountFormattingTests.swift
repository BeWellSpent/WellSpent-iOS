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
}
