import Foundation
import SwiftUI
import WellSpentAPI

/// Formatting shared by every row that shows a fixed-expense template's next
/// due date — Plan's Fixed Expenses list (`PlanFixedExpenseRow`) is the one
/// remaining caller.
///
/// This used to also carry `notDue(...)`, a period-scoped filter for the old
/// Fixed tab's "Future" section (templates with no spawned transaction yet
/// this period). That section was period-scoped by nature; Plan's
/// Fixed-template list isn't — it's profile-level management, not "what's
/// coming up this period" — so every active template shows here regardless,
/// and `notDue(...)` had no remaining caller once that was decided. Removed
/// rather than left unused (confirmed via grep first — see
/// docs/features/overview-plan-navigation-rework.md's Stage 3 notes).
nonisolated enum UpcomingFixedExpenses {
    /// The next due date, formatted for the row caption. Empty when the
    /// backend didn't supply one.
    static func nextDueText(
        for expense: Wellspent_V1_FixedExpense,
        localeIdentifier: String
    ) -> String {
        NextDueDateFormatting.text(
            expense.hasNextDueDate ? expense.nextDueDate : nil,
            localeIdentifier: localeIdentifier
        )
    }
}
