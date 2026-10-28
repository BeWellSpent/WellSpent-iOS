import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The Overview sub-tab's totals block — Income/Actual/Planned/Remaining/
/// Over budget/Unplanned. Rendered as the first `Section` inside
/// `ExpenseOverviewChartListView`'s `List`, so it's part of the same
/// single-scrolling panel as the chart, not a separate strip (see that
/// view's doc comment for the full layout history — this was briefly an
/// always-visible strip pinned above the sub-tab picker, which read live as
/// a disconnected third panel rather than part of Overview).
///
/// The figures themselves are unchanged, still read straight off the shared
/// `ExpenseOverviewViewModel` (owned by `BudgetDetailView`, so this view and
/// the rest of `ExpenseOverviewChartListView` both read the same
/// already-loaded instance without a second fetch).
struct ExpenseOverviewTotalsView: View {
    let viewModel: ExpenseOverviewViewModel
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        let income = viewModel.incomeTotal
        let actual = viewModel.totalActual
        let planned = viewModel.totalPlanned
        let actualIncludingSavings = viewModel.totalActualIncludingSavings
        let plannedIncludingSavings = viewModel.totalPlannedIncludingSavings
        let actualRemainder = viewModel.remainderTotal
        let plannedRemainder = viewModel.plannedRemainderTotal
        let overBudget = viewModel.totalOverBudgetAmount
        let unplanned = viewModel.totalUnplannedAmount

        return VStack(spacing: 2) {
            LabeledContent("Income", value: displayText(income))
                .accessibilityIdentifier("overviewIncomeTotal")
            LabeledContent("Actual", value: overviewText(actual))
                .accessibilityIdentifier("overviewActualTotal")
            LabeledContent("Actual (with savings)", value: overviewText(actualIncludingSavings))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewActualIncludingSavingsTotal")
            LabeledContent("Planned", value: displayText(planned))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewPlannedTotal")
            LabeledContent("Planned (with savings)", value: displayText(plannedIncludingSavings))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewPlannedIncludingSavingsTotal")
            if income.units != 0 || income.nanos != 0 {
                // isNegative, not `units < 0`: a -$0.50 remainder has
                // units == 0 and would otherwise read green.
                LabeledContent("Remaining (actual)", value: displayText(actualRemainder))
                    .foregroundStyle(MoneyFormatting.isNegative(units: actualRemainder.units, nanos: actualRemainder.nanos) ? .red : .green)
                    .accessibilityIdentifier("overviewActualRemainderTotal")
                LabeledContent("Remaining (planned)", value: displayText(plannedRemainder))
                    .foregroundStyle(MoneyFormatting.isNegative(units: plannedRemainder.units, nanos: plannedRemainder.nanos) ? .red : .green)
                    .accessibilityIdentifier("overviewPlannedRemainderTotal")
            }
            if overBudget.units != 0 || overBudget.nanos != 0 {
                LabeledContent("Over budget", value: displayText(overBudget))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("overviewOverBudgetTotal")
            }
            if unplanned.units != 0 || unplanned.nanos != 0 {
                LabeledContent("Unplanned", value: displayText(unplanned))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("overviewUnplannedTotal")
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func displayText(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }

    /// Actual-spend amounts, which are the only ones here that can net
    /// negative — see `ExpenseOverviewChartListView`'s identical helper.
    private func overviewText(_ amount: (units: Int64, nanos: Int32)) -> String {
        OverviewAmountFormatting.text(amount, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}

#Preview {
    ExpenseOverviewTotalsView(
        viewModel: ExpenseOverviewViewModel(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            currencyCode: "USD",
            localeIdentifier: "en",
            currentUserID: nil,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        ),
        currencyCode: "USD",
        localeIdentifier: "en"
    )
}
