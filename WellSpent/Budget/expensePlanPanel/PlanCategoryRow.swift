import SwiftUI
import WellSpentAPI

/// One planned category: where its amount comes from (Manual, From fixed
/// expenses, Savings), a bar split into fixed bills (solid) and other spending
/// (light), and, with both, how much of the manual amount fixed bills take.
/// A category with only a not-yet-due bill is muted and counts toward nothing.
struct PlanCategoryRow: View {
    let category: Wellspent_V1_Category
    let viewModel: ExpensePlanViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onTap: () -> Void

    private typealias Calc = ExpensePlanCalculations

    var body: some View {
        let planned = viewModel.plannedTotal(for: category)
        let notDue = viewModel.notDuePlannedTotal(for: category)
        let total = Calc.categoryTotal(planned: planned, notDue: notDue)
        let allocated = viewModel.allocatedTotal(for: category)
        let fixedDue = viewModel.fixedDueTotal(for: category)
        let isSavings = category.isSystem(.savings)
        let source = Calc.source(allocated: allocated, fixedDue: fixedDue)
        let tint = category.color.isEmpty ? Color.accentColor : Color(hexString: category.color)

        let row = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ColorDotView(hex: category.color, diameter: 10)
                Text(category.displayName)
                    .foregroundStyle(.primary)
                tag(isSavings: isSavings, source: source)
                Spacer()
                Text(format(total.amount))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            splitBar(fixed: fixedFraction(source: source, allocated: allocated, fixedDue: fixedDue, isSavings: isSavings, isNotDue: total.isNotDue), tint: tint)
                .padding(.leading, 20)
            note(total: total, source: source, allocated: allocated, fixedDue: fixedDue)
                .padding(.leading, 20)
        }
        .padding(.vertical, 10)
        .opacity(total.isNotDue ? 0.55 : 1)
        .contentShape(Rectangle())

        Group {
            if canEdit {
                Button(action: onTap) { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
        }
        .accessibilityIdentifier("planCategoryRow_\(category.name)")
    }

    @ViewBuilder
    private func tag(isSavings: Bool, source: Calc.PlanAmountSource) -> some View {
        if isSavings {
            sourceTag(Text("Savings"), tint: .green)
        } else {
            switch source {
            case .manual, .manualAndFixed:
                sourceTag(Text("Manual"), tint: .accentColor)
            case .fixed:
                sourceTag(Text("From fixed expenses"), tint: .secondary)
            case .none:
                EmptyView()
            }
        }
    }

    private func sourceTag(_ text: Text, tint: Color) -> some View {
        text
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
            .accessibilityIdentifier("planCategorySource_\(category.name)")
    }

    /// How much of the bar is fixed bills; the rest is other spending.
    private func fixedFraction(source: Calc.PlanAmountSource, allocated: (units: Int64, nanos: Int32), fixedDue: (units: Int64, nanos: Int32), isSavings: Bool, isNotDue: Bool) -> Double {
        if isSavings { return 0 }
        if isNotDue { return 1 }
        switch source {
        case .fixed: return 1
        case .manual, .none: return 0
        case .manualAndFixed: return HomeOverviewCalculations.fraction(fixedDue, of: allocated)
        }
    }

    private func splitBar(fixed: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            HStack(spacing: fixed > 0 && fixed < 1 ? 2 : 0) {
                Rectangle().fill(tint).frame(width: proxy.size.width * fixed)
                Rectangle().fill(tint.opacity(0.35))
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func note(total: (amount: (units: Int64, nanos: Int32), isNotDue: Bool), source: Calc.PlanAmountSource, allocated: (units: Int64, nanos: Int32), fixedDue: (units: Int64, nanos: Int32)) -> some View {
        if total.isNotDue {
            let dueText = viewModel.nextDueText(for: category)
            if !dueText.isEmpty {
                Text("Not due this period — next due \(dueText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("planCategoryNotDue_\(category.name)")
            }
        } else if source == .manualAndFixed {
            let room = Calc.roomLeft(allocated: allocated, fixedDue: fixedDue)
            let over = MoneyFormatting.isNegative(units: room.units, nanos: room.nanos)
            let roomText = format(over ? (-room.units, -room.nanos) : room)
            (over
                ? Text("\(format(fixedDue)) fixed · \(roomText) over the manual amount")
                : Text("\(format(fixedDue)) fixed · \(roomText) other spending"))
                .font(.caption)
                .foregroundStyle(over ? .orange : .secondary)
                .monospacedDigit()
                .accessibilityIdentifier("planCategoryBreakdown_\(category.name)")
        }
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
