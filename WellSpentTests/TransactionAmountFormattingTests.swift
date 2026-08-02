import Testing
@testable import WellSpent

@Suite("TransactionAmountFormatting")
struct TransactionAmountFormattingTests {
    @Test("positive amounts are Spent")
    func positiveIsSpent() {
        #expect(!TransactionAmountFormatting.isReceived(units: 50, nanos: 0))
        #expect(!TransactionAmountFormatting.isReceived(units: 0, nanos: 500_000_000))
    }

    @Test("negative amounts are Received")
    func negativeIsReceived() {
        #expect(TransactionAmountFormatting.isReceived(units: -50, nanos: 0))
        #expect(TransactionAmountFormatting.isReceived(units: 0, nanos: -500_000_000))
    }

    @Test("zero is Spent, not Received")
    func zeroIsSpent() {
        #expect(!TransactionAmountFormatting.isReceived(units: 0, nanos: 0))
    }

    @Test("Spent amounts display with a minus prefix")
    func spentDisplayText() {
        let text = TransactionAmountFormatting.displayText(units: 50, nanos: 0, currencyCode: "USD", localeIdentifier: "en_US")
        #expect(text.hasPrefix("-"))
        #expect(text.contains("50"))
    }

    @Test("Received amounts display with a plus prefix and the absolute value")
    func receivedDisplayText() {
        let text = TransactionAmountFormatting.displayText(units: -50, nanos: 0, currencyCode: "USD", localeIdentifier: "en_US")
        #expect(text.hasPrefix("+"))
        #expect(text.contains("50"))
        #expect(!text.contains("--"))
    }

    @Test("sum carries nanos overflow into units")
    func sumCarriesOverflow() {
        let result = TransactionAmountFormatting.sum([
            (units: 1, nanos: 600_000_000),
            (units: 1, nanos: 600_000_000)
        ])
        #expect(result.units == 3)
        #expect(result.nanos == 200_000_000)
    }

    @Test("sum carries nanos underflow into units for negative amounts")
    func sumCarriesUnderflow() {
        let result = TransactionAmountFormatting.sum([
            (units: -1, nanos: -600_000_000),
            (units: -1, nanos: -600_000_000)
        ])
        #expect(result.units == -3)
        #expect(result.nanos == -200_000_000)
    }

    @Test("sum of an empty list is zero")
    func sumOfEmptyIsZero() {
        let result = TransactionAmountFormatting.sum([])
        #expect(result.units == 0)
        #expect(result.nanos == 0)
    }

    @Test("sum of many large-nanos entries doesn't overflow the accumulator")
    func sumDoesNotOverflowWithManyLargeNanosEntries() {
        // Regression test for a production crash: accumulating nanos as
        // Int32 during the loop (instead of Int64) trapped with a fatal
        // arithmetic-overflow error once the running total exceeded
        // Int32.max (~2.147B) — three entries at 999,999,999 each already
        // does that (2,999,999,997), well within a realistic number of
        // income sources/categories on the Plan tab.
        let result = TransactionAmountFormatting.sum([
            (units: 0, nanos: 999_999_999),
            (units: 0, nanos: 999_999_999),
            (units: 0, nanos: 999_999_999)
        ])
        #expect(result.units == 2)
        #expect(result.nanos == 999_999_997)
    }
}
