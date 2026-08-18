import Foundation
import WellSpentAPI

/// Which fixed-expense templates are upcoming rather than due this period.
///
/// Mirrors web's `notDueFixedExpenses` in `transactionsPanel/helpers.ts`
/// exactly — this is the one derived fact both clients have to agree on for
/// the Fixed tab's "Future" section to mean the same thing on each.
nonisolated enum UpcomingFixedExpenses {
    /// Active templates with no transaction in this period.
    ///
    /// "No transaction this period" is a sound proxy for "not due this
    /// period": `createNextPeriod` spawns a transaction at period start for
    /// everything due within it, so a template with nothing here is genuinely
    /// next due in a later period. A template created mid-period spawns
    /// immediately when it's already due, and a deactivated one drops out via
    /// `isActive` while its existing transaction stays.
    ///
    /// That reasoning only holds for the *live* period. `ListFixedExpenses` is
    /// scoped to the profile, not the period, so on an archived period this
    /// would list every template created since — reporting bills as "upcoming"
    /// in a month that already ended. Nothing is upcoming in a closed period,
    /// so the whole section is suppressed there rather than shown wrong.
    static func notDue(
        expenses: [Wellspent_V1_FixedExpense],
        transactions: [Wellspent_V1_Transaction],
        isArchivedPeriod: Bool = false
    ) -> [Wellspent_V1_FixedExpense] {
        guard !isArchivedPeriod else { return [] }
        let spawnedIDs = Set(transactions.map(\.fixedExpenseID))
        return expenses
            .filter { $0.isActive && !spawnedIDs.contains($0.id) }
            // Soonest first. These arrive in ListFixedExpenses' `ORDER BY
            // name`, which says nothing about what is about to be charged
            // (issue #48). A template with no next due date sorts last rather
            // than jumping to the front as a zero timestamp would.
            .sorted { nextDueSortKey($0) < nextDueSortKey($1) }
    }

    private static func nextDueSortKey(_ expense: Wellspent_V1_FixedExpense) -> Int64 {
        expense.hasNextDueDate ? expense.nextDueDate.seconds : .max
    }

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
