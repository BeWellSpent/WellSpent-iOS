import SwiftUI
import WellSpentAPI

/// One fixed-expense template in Plan: name, kind tag and amount; its schedule
/// and next due date; category and payment method; and, for a payment plan,
/// progress and end date (orange when it ends soon). Tapping edits it.
struct PlanFixedExpenseRow: View {
    let expense: Wellspent_V1_FixedExpense
    let viewModel: FixedExpenseTemplatesViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ColorDotView(hex: viewModel.categoryColor(for: expense.categoryID), diameter: 10)
                Text(expense.name)
                if let kind = FixedExpensePlanSummary.kind(for: expense) {
                    (kind == .installments ? Text("Installments") : Text("Payment plan"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .accessibilityIdentifier("fixedExpenseKind_\(expense.name)")
                }
                Spacer()
                Text(MoneyFormatting.format(
                    units: expense.plannedAmount.units,
                    nanos: expense.plannedAmount.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))
                .fontWeight(.semibold)
                .monospacedDigit()
            }

            Group {
                let nextDue = UpcomingFixedExpenses.nextDueText(for: expense, localeIdentifier: localeIdentifier)
                let schedule = FixedExpenseScheduling.scheduleSummary(
                    intervalMonths: expense.intervalMonths,
                    intervalWeeks: expense.intervalWeeks,
                    frequencyUnit: expense.frequencyUnit
                )
                if nextDue.isEmpty {
                    Text(schedule)
                } else {
                    Text("\(schedule) · due \(nextDue)")
                        .accessibilityIdentifier("upcomingFixedExpenseDue_\(expense.name)")
                }
                details
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, 20)

            planProgress
                .padding(.leading, 20)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        // Whole-row tap via .simultaneousGesture, not .onTapGesture or a
        // row-spanning Button: both lose to the row's .swipeActions (see
        // FixedExpenseRow and this repo's CLAUDE.md).
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { if canEdit { onEdit() } })
        .accessibilityAddTraits(canEdit ? .isButton : [])
        .accessibilityIdentifier("upcomingFixedExpenseRow_\(expense.name)")
    }

    private var details: some View {
        let parts = [viewModel.categoryName(for: expense.categoryID), viewModel.paymentMethodName(for: expense.paymentMethodID)].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
    }

    @ViewBuilder
    private var planProgress: some View {
        if FixedExpensePlanSummary.kind(for: expense) != nil {
            let endingSoon = FixedExpensePlanSummary.isEndingSoon(expense)
            VStack(alignment: .leading, spacing: 4) {
                if expense.totalPayments > 0 {
                    ProgressView(value: Double(expense.paymentsMade), total: Double(expense.totalPayments))
                        .tint(endingSoon ? .orange : .accentColor)
                }
                HStack(spacing: 4) {
                    if let progress = FixedExpensePlanSummary.progressText(for: expense) {
                        Text(progress)
                            .accessibilityIdentifier("fixedExpenseProgress_\(expense.name)")
                    }
                    if let ends = FixedExpensePlanSummary.endsText(for: expense, localeIdentifier: localeIdentifier) {
                        if FixedExpensePlanSummary.progressText(for: expense) != nil { Text("·") }
                        Text(ends)
                            .fontWeight(endingSoon ? .semibold : .regular)
                            .foregroundStyle(endingSoon ? .orange : .secondary)
                            .accessibilityIdentifier("fixedExpenseEnds_\(expense.name)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }
}
