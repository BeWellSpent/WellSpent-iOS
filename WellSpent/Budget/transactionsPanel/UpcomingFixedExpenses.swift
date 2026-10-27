import Foundation
import SwiftUI
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

/// A fixed-expense template that isn't due in this period yet.
///
/// Tapping it edits the template and swiping deletes it, matching web — there
/// is no spawned transaction, so both act on the template directly. Mark-paid
/// is still absent: there is nothing to pay yet. Muted so an upcoming bill
/// can't be mistaken for something already owed.
///
/// Extracted out of `FixedExpensesListView` when Stage 2 of
/// docs/features/overview-plan-navigation-rework.md merged that screen's
/// Unpaid/Paid sections into the Transactions list. The Future section this
/// row belongs to is explicitly out of scope for Stage 2 — nothing has
/// happened yet for a Future row, so it moves to Plan in Stage 3 alongside
/// Fixed-template management. Co-located here (not deleted) so that stage
/// can reuse it directly; currently unreferenced from any view.
struct UpcomingFixedExpenseRow: View {
    let expense: Wellspent_V1_FixedExpense
    let viewModel: FixedExpensesViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Group {
                    if canEdit {
                        Button(action: onEdit) {
                            Text(expense.name)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(expense.name)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(MoneyFormatting.format(
                    units: expense.plannedAmount.units,
                    nanos: expense.plannedAmount.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                let nextDue = UpcomingFixedExpenses.nextDueText(for: expense, localeIdentifier: localeIdentifier)
                if !nextDue.isEmpty {
                    Text("Due \(nextDue)")
                        .accessibilityIdentifier("upcomingFixedExpenseDue_\(expense.name)")
                }
                if let categoryName = viewModel.categoryName(for: expense.categoryID) {
                    if !nextDue.isEmpty { Text("·") }
                    ColorDotView(hex: viewModel.categoryColor(for: expense.categoryID), diameter: 8)
                    Text(categoryName)
                }
                if let methodName = viewModel.paymentMethodName(for: expense.paymentMethodID) {
                    Text("·")
                    Text(methodName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("upcomingFixedExpenseRow_\(expense.name)")
    }
}
