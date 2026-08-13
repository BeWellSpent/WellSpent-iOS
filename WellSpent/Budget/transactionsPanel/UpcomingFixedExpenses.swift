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
        return expenses.filter { $0.isActive && !spawnedIDs.contains($0.id) }
    }

    /// The next due date, formatted for the row caption. Empty when the
    /// backend didn't supply one.
    ///
    /// Read through `dateOnly`, never the raw timestamp: `next_due_date` is a
    /// DATE-only value the backend encodes as midnight UTC, so interpreting it
    /// in a timezone behind UTC lands a day early (see `Shared/DateOnly.swift`).
    static func nextDueText(
        for expense: Wellspent_V1_FixedExpense,
        localeIdentifier: String
    ) -> String {
        guard expense.hasNextDueDate else { return "" }
        return expense.nextDueDate.dateOnly.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(Locale(identifier: localeIdentifier))
        )
    }
}
