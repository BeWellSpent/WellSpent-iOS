import Testing
@testable import WellSpent

@Suite("MoneyFormatting")
struct MoneyFormattingTests {
    @Test("formats a whole-dollar USD amount")
    func wholeUSD() {
        let result = MoneyFormatting.format(units: 100, nanos: 0, currencyCode: "USD", localeIdentifier: "en_US")
        #expect(result == "$100.00")
    }

    @Test("formats a fractional amount")
    func fractional() {
        let result = MoneyFormatting.format(units: 19, nanos: 990_000_000, currencyCode: "USD", localeIdentifier: "en_US")
        #expect(result == "$19.99")
    }

    @Test("formats zero")
    func zero() {
        let result = MoneyFormatting.format(units: 0, nanos: 0, currencyCode: "USD", localeIdentifier: "en_US")
        #expect(result == "$0.00")
    }

    @Test("formats a negative amount, including the sign")
    func negative() {
        let result = MoneyFormatting.format(units: -50, nanos: 0, currencyCode: "USD", localeIdentifier: "en_US")
        #expect(result.contains("50"))
        #expect(result.contains("-"))
    }

    @Test("still returns a non-empty string for an unrecognized currency code")
    func unknownCurrencyCode() {
        let result = MoneyFormatting.format(units: 10, nanos: 0, currencyCode: "NOTACODE", localeIdentifier: "en_US")
        #expect(!result.isEmpty)
        #expect(result.contains("10"))
    }

    @Test("formats a non-USD currency in its own locale")
    func nonUSDCurrency() {
        let result = MoneyFormatting.format(units: 100, nanos: 0, currencyCode: "EUR", localeIdentifier: "es_AR")
        #expect(result.contains("100"))
    }

    // A -$0.50 amount is units == 0, nanos == -500_000_000. A units-only check
    // calls that non-negative, which mis-coloured a small negative remainder
    // green on both the Overview and the Plan tab.
    @Test("isNegative catches a sub-unit negative that a units-only check misses")
    func isNegativeSubUnit() {
        #expect(MoneyFormatting.isNegative(units: 0, nanos: -500_000_000))
        #expect(MoneyFormatting.isNegative(units: -1, nanos: 0))
        #expect(!MoneyFormatting.isNegative(units: 0, nanos: 0))
        #expect(!MoneyFormatting.isNegative(units: 0, nanos: 500_000_000))
    }
}
