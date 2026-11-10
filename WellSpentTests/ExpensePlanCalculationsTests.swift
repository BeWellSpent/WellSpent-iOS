import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ExpensePlanCalculations")
struct ExpensePlanCalculationsTests {
    private func money(_ units: Int64, _ nanos: Int32 = 0) -> Wellspent_V1_Money {
        .with { $0.units = units; $0.nanos = nanos; $0.currency = "USD" }
    }

    @Test("categoryTotal shows the planned amount when there is one")
    func categoryTotalPrefersPlanned() {
        let result = ExpensePlanCalculations.categoryTotal(
            planned: (units: 400, nanos: 0),
            notDue: (units: 120, nanos: 0)
        )

        #expect(result.amount.units == 400)
        #expect(!result.isNotDue)
    }

    @Test("categoryTotal falls back to the upcoming amount, flagged as not due")
    func categoryTotalFallsBackToNotDue() {
        // The row still shows a number so the category doesn't read as empty,
        // but the flag is what stops it being mistaken for a plan — this
        // amount counts toward the Committed total not at all (issue #48).
        let result = ExpensePlanCalculations.categoryTotal(
            planned: (units: 0, nanos: 0),
            notDue: (units: 120, nanos: 0)
        )

        #expect(result.amount.units == 120)
        #expect(result.isNotDue)
    }

    @Test("categoryTotal treats a sub-dollar plan as a real plan")
    func categoryTotalRespectsNanosOnlyPlan() {
        // Guards a units-only zero check, which would silently prefer the
        // upcoming amount over a real 50-cent allocation.
        let result = ExpensePlanCalculations.categoryTotal(
            planned: (units: 0, nanos: 500_000_000),
            notDue: (units: 120, nanos: 0)
        )

        #expect(result.amount.nanos == 500_000_000)
        #expect(!result.isNotDue)
    }

    @Test("categoryTotal reports zero when nothing is planned or upcoming")
    func categoryTotalZero() {
        let result = ExpensePlanCalculations.categoryTotal(
            planned: (units: 0, nanos: 0),
            notDue: (units: 0, nanos: 0)
        )

        #expect(result.amount.units == 0)
        #expect(!result.isNotDue)
    }

    @Test("source says manual, fixed, both or neither")
    func sourceClassification() {
        let none = (units: Int64(0), nanos: Int32(0))
        let some = (units: Int64(268), nanos: Int32(0))
        #expect(ExpensePlanCalculations.source(allocated: some, fixedDue: none) == .manual)
        #expect(ExpensePlanCalculations.source(allocated: none, fixedDue: some) == .fixed)
        #expect(ExpensePlanCalculations.source(allocated: some, fixedDue: some) == .manualAndFixed)
        #expect(ExpensePlanCalculations.source(allocated: none, fixedDue: none) == .none)
        // A sub-dollar amount is still an amount.
        #expect(ExpensePlanCalculations.source(allocated: (0, 500_000_000), fixedDue: none) == .manual)
    }

    @Test("roomLeft is manual minus fixed, negative when fixed bills exceed the manual amount")
    func roomLeft() {
        let room = ExpensePlanCalculations.roomLeft(allocated: (500, 0), fixedDue: (268, 0))
        #expect(room.units == 232 && room.nanos == 0)
        let over = ExpensePlanCalculations.roomLeft(allocated: (200, 0), fixedDue: (250, 0))
        #expect(over.units == -50 && over.nanos == 0)
        // Cents borrow across the unit boundary: 10.25 - 3.50 = 6.75, and 3.00 - 3.50 = -0.50.
        let cents = ExpensePlanCalculations.roomLeft(allocated: (10, 250_000_000), fixedDue: (3, 500_000_000))
        #expect(cents.units == 6 && cents.nanos == 750_000_000)
        let subDollar = ExpensePlanCalculations.roomLeft(allocated: (3, 0), fixedDue: (3, 500_000_000))
        #expect(subDollar.units == 0 && subDollar.nanos == -500_000_000)
    }
}
