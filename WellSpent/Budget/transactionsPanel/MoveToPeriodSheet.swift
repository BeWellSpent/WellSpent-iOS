import SwiftUI
import WellSpentAPI

/// Lets a swipe action reassign a transaction to a different period. Reachable
/// only via the leading swipe actions on Variable/Fixed/Payments rows (issue
/// #104) — no always-visible row button. Periods are passed in already
/// loaded (`BudgetDetailViewModel.periods`); no new fetch here.
struct MoveToPeriodSheet: View {
    let transaction: Wellspent_V1_Transaction
    let periods: [Wellspent_V1_BudgetPeriod]
    let localeIdentifier: String
    let onSelect: (Wellspent_V1_BudgetPeriod) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Any period but the one it's already in; closed periods are editable (#120).
    private var selectablePeriods: [Wellspent_V1_BudgetPeriod] {
        periods.filter { $0.id != transaction.budgetPeriodID }
    }

    var body: some View {
        NavigationStack {
            List(selectablePeriods, id: \.id) { period in
                Button {
                    dismiss()
                    onSelect(period)
                } label: {
                    Text(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("moveToPeriod_option_\(period.id)")
            }
            .sheetChrome(Text("Move to Period")) { dismiss() }
        }
        .presentationDetents([.medium, .large])
    }
}
