import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The Overview screen's totals block — Income/Actual/Planned/Remaining/
/// Over budget/Unplanned — pulled to the top of the screen, always visible
/// regardless of which Transactions/Payments/Review sub-tab is selected
/// (correction to Stage 1 of
/// docs/features/overview-plan-navigation-rework.md: the chart and this
/// totals block used to be one of the sub-tab picker's own segments,
/// replacing the whole screen when another segment was picked).
///
/// Split out of what used to be `ExpenseOverviewListView`'s own trailing
/// `Section` — the figures themselves are unchanged, still read straight off
/// the shared `ExpenseOverviewViewModel` (owned by `BudgetDetailView` now, so
/// this view and `ExpenseOverviewChartListView` below can both read the same
/// already-loaded instance without a second fetch).
struct ExpenseOverviewTotalsView: View {
    let viewModel: ExpenseOverviewViewModel
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        let income = viewModel.incomeTotal
        let actual = viewModel.totalActual
        let planned = viewModel.totalPlanned
        let actualRemainder = viewModel.remainderTotal
        let plannedRemainder = viewModel.plannedRemainderTotal
        let overBudget = viewModel.totalOverBudgetAmount
        let unplanned = viewModel.totalUnplannedAmount

        return VStack(spacing: 2) {
            LabeledContent("Income", value: displayText(income))
                .accessibilityIdentifier("overviewIncomeTotal")
            LabeledContent("Actual", value: overviewText(actual))
                .accessibilityIdentifier("overviewActualTotal")
            LabeledContent("Planned", value: displayText(planned))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewPlannedTotal")
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
