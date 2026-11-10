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
    /// Where a Plan row's planned amount comes from. The server picks the
    /// manual amount when there is one and otherwise the fixed expenses due
    /// this period; they never add, so both can exist at once.
    enum PlanAmountSource: Equatable {
        case none
        case manual
        case fixed
        case manualAndFixed
    }

    static func source(
        allocated: (units: Int64, nanos: Int32),
        fixedDue: (units: Int64, nanos: Int32)
    ) -> PlanAmountSource {
        let hasManual = allocated.units != 0 || allocated.nanos != 0
        let hasFixed = fixedDue.units != 0 || fixedDue.nanos != 0
        switch (hasManual, hasFixed) {
        case (true, true): return .manualAndFixed
        case (true, false): return .manual
        case (false, true): return .fixed
        case (false, false): return .none
        }
    }

    /// Manual amount minus what fixed expenses already take: positive is room
    /// left for other spending, negative is how far fixed bills exceed the
    /// manual amount. Signs of units and nanos always agree.
    static func roomLeft(
        allocated: (units: Int64, nanos: Int32),
        fixedDue: (units: Int64, nanos: Int32)
    ) -> (units: Int64, nanos: Int32) {
        let nanosPerUnit: Int64 = 1_000_000_000
        let diff = (allocated.units - fixedDue.units) * nanosPerUnit + Int64(allocated.nanos - fixedDue.nanos)
        return (diff / nanosPerUnit, Int32(diff % nanosPerUnit))
    }

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
