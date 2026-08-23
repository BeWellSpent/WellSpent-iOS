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
}
