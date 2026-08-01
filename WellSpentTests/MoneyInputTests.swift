import Testing
@testable import WellSpent

@Suite("MoneyInput")
struct MoneyInputTests {
    @Test("parses whole and fractional amounts into units/nanos")
    func parseAmount() {
        let whole = MoneyInput.parseAmount("2500")
        #expect(whole?.units == 2500)
        #expect(whole?.nanos == 0)

        let fractional = MoneyInput.parseAmount("2500.5")
        #expect(fractional?.units == 2500)
        #expect(fractional?.nanos == 500_000_000)
    }

    @Test("rejects empty, non-numeric, or negative amounts")
    func parseAmountRejectsInvalid() {
        #expect(MoneyInput.parseAmount("") == nil)
        #expect(MoneyInput.parseAmount("abc") == nil)
        #expect(MoneyInput.parseAmount("-5") == nil)
    }

    @Test("formats whole and fractional units/nanos back into editable strings")
    func formatForEditing() {
        #expect(MoneyInput.formatForEditing(units: 1200, nanos: 0) == "1200")
        #expect(MoneyInput.formatForEditing(units: 19, nanos: 990_000_000) == "19.99")
    }
}
