import WellSpentAPI

/// Small shared predicates for the Expense Overview tab. The actual
/// planned/actual/remainder/over-budget/unplanned totals now come from the
/// backend's `GetExpenseSummary` RPC (see docs/features/expense-summary.md,
/// issue #35) — this enum keeps only what's still genuinely client-side:
/// the transaction-exclusion rule (used to filter the raw per-category
/// drill-down transaction list, not to compute a total) and the trivial
/// actual-vs-planned comparison (used for a display-only per-person
/// over/under indicator; the category-level equivalent is now the server's
/// `CategoryExpenseSummary.isOver` field directly).
nonisolated enum ExpenseOverviewCalculations {
    /// A transaction is excluded from totals if manually flagged, or if its
    /// category is the system "Income" category — regardless of the flag
    /// (docs/features/transactions.md).
    static func isTransactionExcluded(_ transaction: Wellspent_V1_Transaction, incomeCategoryID: Int32?) -> Bool {
        transaction.isExcluded || (incomeCategoryID != nil && transaction.categoryID == incomeCategoryID)
    }

    static func isOver(actual: (units: Int64, nanos: Int32), planned: (units: Int64, nanos: Int32)) -> Bool {
        let plannedValue = Double(planned.units) + Double(planned.nanos) / 1_000_000_000
        guard plannedValue > 0 else { return false }
        let actualValue = Double(actual.units) + Double(actual.nanos) / 1_000_000_000
        return actualValue > plannedValue
    }
}
