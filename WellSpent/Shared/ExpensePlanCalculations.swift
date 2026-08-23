import WellSpentAPI

/// Pure display derivation for the Expense Plan tab. Kept free of
/// network/view-model state so it's directly testable.
///
/// Once the home of this tab's planned-total math; almost all of it moved to
/// `GetExpenseSummary` (issue #35), and `plannedTotal` — the last piece, kept
/// alive only by the Transactions tab's "Exceeded only" filter — went with it
/// in #61. What remains is genuinely presentational: which of two amounts a
/// row shows, and how to say so.
nonisolated enum ExpensePlanCalculations {
    /// What a Plan row's amount column shows: the planned amount, or — when
    /// nothing is planned but a bill is coming — the upcoming amount, flagged
    /// so the view can mute it and caption it with a due date.
    ///
    /// Mirrors web's `categoryTotalDisplay` (expensesPanel/helpers.ts). The
    /// two numbers must not be confused for one another: the planned amount
    /// counts toward the Committed total under the list, the upcoming one
    /// counts toward nothing at all (issue #48).
    static func categoryTotal(
        planned: (units: Int64, nanos: Int32),
        notDue: (units: Int64, nanos: Int32)
    ) -> (amount: (units: Int64, nanos: Int32), isNotDue: Bool) {
        if planned.units != 0 || planned.nanos != 0 {
            return (planned, false)
        }
        if notDue.units != 0 || notDue.nanos != 0 {
            return (notDue, true)
        }
        return ((0, 0), false)
    }

}
