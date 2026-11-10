import SwiftUI

/// Planned income and planned expenses with and without savings, with a bar
/// showing how planned income splits into expenses, savings and what's left.
struct HomePlanCard: View {
    let viewModel: ExpenseOverviewViewModel
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        let income = viewModel.plannedIncome
        let withSavings = viewModel.plannedExpensesIncludingSavings
        let withoutSavings = viewModel.plannedExpenses
        let savings = TransactionAmountFormatting.sum([withSavings, (units: -withoutSavings.units, nanos: -withoutSavings.nanos)])

        HomeCard {
            allocationBar(
                expenses: HomeOverviewCalculations.fraction(withoutSavings, of: income),
                savings: HomeOverviewCalculations.fraction(savings, of: income)
            )
            .padding(.bottom, 4)

            row(Text("Income"), amount: income, emphasized: true, id: "homePlannedIncome")
            row(Text("Expenses with savings"), amount: withSavings, dot: .green, id: "homePlannedWithSavings")
            row(Text("Expenses without savings"), amount: withoutSavings, dot: .accentColor, id: "homePlannedWithoutSavings")

            if let notPlanned = viewModel.notPlannedYet {
                Divider()
                LabeledContent {
                    Text(format(notPlanned))
                        .fontWeight(.semibold)
                        .foregroundStyle(MoneyFormatting.isNegative(units: notPlanned.units, nanos: notPlanned.nanos) ? .red : .green)
                } label: {
                    Text("Not planned yet").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityIdentifier("homeNotPlannedYet")
            }
        }
    }

    private func row(_ label: Text, amount: (units: Int64, nanos: Int32), emphasized: Bool = false, dot: Color? = nil, id: String) -> some View {
        LabeledContent {
            Text(format(amount))
                .fontWeight(emphasized ? .bold : .semibold)
                .foregroundStyle(.primary)
        } label: {
            HStack(spacing: 8) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                label.foregroundStyle(.primary)
            }
        }
        .monospacedDigit()
        .accessibilityIdentifier(id)
    }

    /// Expenses, then savings, then the unplanned remainder as the empty track.
    private func allocationBar(expenses: Double, savings: Double) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Rectangle().fill(Color.accentColor).frame(width: proxy.size.width * expenses)
                Rectangle().fill(Color.green).frame(width: proxy.size.width * savings)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
