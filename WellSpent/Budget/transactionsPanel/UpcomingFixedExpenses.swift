import Foundation
import SwiftUI
import WellSpentAPI

/// Formatting shared by every row that shows a fixed-expense template's next
/// due date — Plan's Fixed Expenses list (`UpcomingFixedExpenseRow`, below)
/// is the one remaining caller.
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

/// A row in Plan's Fixed Expenses list — one active recurring-bill template.
/// Tapping it edits the template and swiping deletes it (deactivates); there
/// is no mark-paid here, since this is template management, not an
/// occurrence (that's Overview's Transactions sub-tab's job).
///
/// Extracted out of `FixedExpensesListView` during Stage 2 of
/// docs/features/overview-plan-navigation-rework.md, reserved unreferenced
/// for Stage 3 — now wired into Plan's Fixed Expenses sub-tab (Stage 3).
struct UpcomingFixedExpenseRow: View {
    let expense: Wellspent_V1_FixedExpense
    let viewModel: FixedExpenseTemplatesViewModel
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

            Text(FixedExpenseScheduling.scheduleSummary(
                intervalMonths: expense.intervalMonths,
                intervalWeeks: expense.intervalWeeks,
                frequencyUnit: expense.frequencyUnit
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

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
