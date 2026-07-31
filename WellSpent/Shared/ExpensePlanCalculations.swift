import WellSpentAPI

/// Pure planned-total derivation for the Expense Plan tab, mirroring web's
/// `getCatPlanned`/`computeCategoryRow` (WellSpent-web/src/components/budget/
/// expensesPanel/helpers.ts). Kept free of network/view-model state so it's
/// directly testable.
nonisolated enum ExpensePlanCalculations {
    /// Matches the "Savings" system category special-case already used for
    /// the Income category (see docs/features/transactions.md).
    static func isSavingsCategory(_ category: Wellspent_V1_Category) -> Bool {
        category.isSystem && category.name == "Savings"
    }

    /// Planned total for a single category:
    /// 1. Savings category -> sum of savings source amounts.
    /// 2. Else -> sum of this category's `ExpenseAllocation.plannedAmount` across people.
    /// 3. If that sum is zero -> fall back to the sum of current-period Fixed
    ///    transactions' `plannedAmount` for this category.
    /// Allocations and the fixed fallback are never combined for the same category.
    static func plannedTotal(
        for categoryID: Int32,
        isSavings: Bool,
        allocations: [Wellspent_V1_ExpenseAllocation],
        savingsAmounts: [(units: Int64, nanos: Int32)],
        fixedPlannedAmounts: [(units: Int64, nanos: Int32)]
    ) -> (units: Int64, nanos: Int32) {
        if isSavings {
            return TransactionAmountFormatting.sum(savingsAmounts)
        }

        let allocationAmounts = allocations
            .filter { $0.categoryID == categoryID }
            .map { (units: $0.plannedAmount.units, nanos: $0.plannedAmount.nanos) }
        let allocationTotal = TransactionAmountFormatting.sum(allocationAmounts)
        if allocationTotal.units != 0 || allocationTotal.nanos != 0 {
            return allocationTotal
        }

        return TransactionAmountFormatting.sum(fixedPlannedAmounts)
    }

    /// Filters to categories that should appear in the Plan list (has
    /// allocations, is Savings with sources present, or has a nonzero fixed
    /// fallback), then sorts by planned total descending
    /// (docs/features/category-list-order.md).
    static func sortedVisibleCategories(
        categories: [Wellspent_V1_Category],
        plannedTotal: (Wellspent_V1_Category) -> (units: Int64, nanos: Int32)
    ) -> [Wellspent_V1_Category] {
        categories
            .filter { category in
                let total = plannedTotal(category)
                return total.units != 0 || total.nanos != 0
            }
            .sorted { lhs, rhs in
                let lhsTotal = plannedTotal(lhs)
                let rhsTotal = plannedTotal(rhs)
                if lhsTotal.units != rhsTotal.units {
                    return lhsTotal.units > rhsTotal.units
                }
                return lhsTotal.nanos > rhsTotal.nanos
            }
    }
}
