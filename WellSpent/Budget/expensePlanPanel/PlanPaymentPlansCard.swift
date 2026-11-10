import SwiftUI
import WellSpentAPI

/// Payment plans and installments with their progress and end date, ending
/// soonest first (orange when it ends soon). Tapping one edits it.
struct PlanPaymentPlansCard: View {
    let plans: [Wellspent_V1_FixedExpense]
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onEdit: (Wellspent_V1_FixedExpense) -> Void

    var body: some View {
        HomeCard {
            ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                if index > 0 { Divider() }
                Button { onEdit(plan) } label: { row(plan) }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityIdentifier("planPaymentPlan_\(plan.name)")
            }
        }
        .accessibilityIdentifier("planPaymentPlans")
    }

    private func row(_ plan: Wellspent_V1_FixedExpense) -> some View {
        let soon = FixedExpensePlanSummary.isEndingSoon(plan)
        let progress = FixedExpensePlanSummary.progressText(for: plan)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.name)
                Spacer()
                Text("\(MoneyFormatting.format(units: plan.plannedAmount.units, nanos: plan.plannedAmount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)) / period")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            if plan.totalPayments > 0 {
                ProgressView(value: Double(plan.paymentsMade), total: Double(plan.totalPayments))
                    .tint(soon ? .orange : .accentColor)
            }
            HStack(spacing: 4) {
                if let progress { Text(progress) }
                if let ends = FixedExpensePlanSummary.endsText(for: plan, localeIdentifier: localeIdentifier) {
                    if progress != nil { Text("·") }
                    Text(ends)
                        .fontWeight(soon ? .semibold : .regular)
                        .foregroundStyle(soon ? .orange : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
