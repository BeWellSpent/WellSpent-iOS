import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ExpensePlanCalculations")
struct ExpensePlanCalculationsTests {
    private func money(_ units: Int64, _ nanos: Int32 = 0) -> Wellspent_V1_Money {
        .with { $0.units = units; $0.nanos = nanos; $0.currency = "USD" }
    }

    @Test("Savings category sums savings source amounts, ignoring allocations")
    func savingsCategoryUsesSavingsAmounts() {
        let allocations = [
            Wellspent_V1_ExpenseAllocation.with { $0.categoryID = 1; $0.plannedAmount = money(999) }
        ]
        let result = ExpensePlanCalculations.plannedTotal(
            for: 1,
            isSavings: true,
            allocations: allocations,
            savingsAmounts: [(units: 100, nanos: 0), (units: 50, nanos: 0)],
            fixedPlannedAmounts: []
        )
        #expect(result.units == 150)
    }

    @Test("non-Savings category sums allocations across people")
    func nonSavingsUsesAllocations() {
        let allocations = [
            Wellspent_V1_ExpenseAllocation.with { $0.categoryID = 2; $0.plannedAmount = money(100) },
            Wellspent_V1_ExpenseAllocation.with { $0.categoryID = 2; $0.plannedAmount = money(50) },
            Wellspent_V1_ExpenseAllocation.with { $0.categoryID = 3; $0.plannedAmount = money(999) }
        ]
        let result = ExpensePlanCalculations.plannedTotal(
            for: 2,
            isSavings: false,
            allocations: allocations,
            savingsAmounts: [],
            fixedPlannedAmounts: [(units: 5, nanos: 0)]
        )
        #expect(result.units == 150)
    }

    @Test("falls back to fixed-planned total when there are no allocations for the category")
    func fallsBackToFixedWhenNoAllocations() {
        let result = ExpensePlanCalculations.plannedTotal(
            for: 4,
            isSavings: false,
            allocations: [],
            savingsAmounts: [],
            fixedPlannedAmounts: [(units: 20, nanos: 0), (units: 30, nanos: 0)]
        )
        #expect(result.units == 50)
    }

    @Test("zero allocations and zero fixed planned yields zero")
    func zeroWhenNothingPlanned() {
        let result = ExpensePlanCalculations.plannedTotal(
            for: 5,
            isSavings: false,
            allocations: [],
            savingsAmounts: [],
            fixedPlannedAmounts: []
        )
        #expect(result.units == 0)
        #expect(result.nanos == 0)
    }

    @Test("visible categories are filtered to nonzero planned total and sorted descending")
    func sortedVisibleCategoriesFiltersAndSorts() {
        let low = Wellspent_V1_Category.with { $0.id = 1; $0.name = "Low" }
        let high = Wellspent_V1_Category.with { $0.id = 2; $0.name = "High" }
        let zero = Wellspent_V1_Category.with { $0.id = 3; $0.name = "Zero" }
        let totals: [Int32: (units: Int64, nanos: Int32)] = [
            1: (units: 10, nanos: 0),
            2: (units: 100, nanos: 0),
            3: (units: 0, nanos: 0)
        ]

        let result = ExpensePlanCalculations.sortedVisibleCategories(categories: [low, high, zero]) { category in
            totals[category.id] ?? (units: 0, nanos: 0)
        }

        #expect(result.map(\.id) == [2, 1])
    }

    @Test("isSavingsCategory matches only the system Savings category")
    func isSavingsCategoryMatchesSystemSavings() {
        let savings = Wellspent_V1_Category.with {
            $0.name = "Savings"; $0.isSystem = true; $0.systemCategory = .savings
        }
        // A user category the owner happened to call "Savings". Identity comes
        // from systemCategory now, so this must not match.
        let userSavings = Wellspent_V1_Category.with { $0.name = "Savings"; $0.isSystem = false }
        let other = Wellspent_V1_Category.with {
            $0.name = "Groceries"; $0.isSystem = true; $0.systemCategory = .groceries
        }
        // The system Savings category as a Spanish client sees it.
        let translated = Wellspent_V1_Category.with {
            $0.name = "Ahorros"; $0.isSystem = true; $0.systemCategory = .savings
        }

        #expect(ExpensePlanCalculations.isSavingsCategory(savings))
        #expect(ExpensePlanCalculations.isSavingsCategory(translated))
        #expect(!ExpensePlanCalculations.isSavingsCategory(userSavings))
        #expect(!ExpensePlanCalculations.isSavingsCategory(other))
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
