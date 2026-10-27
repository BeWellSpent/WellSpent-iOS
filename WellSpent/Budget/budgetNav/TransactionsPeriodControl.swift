import SwiftUI
import WellSpentAPI

/// The period control in the Transactions screen's header (issue #92
/// follow-up) — relocated from `BudgetMenuSheet.periodSection`, which no
/// longer offers period switching at all; it belongs on the screen it
/// affects, not buried in the ☰ menu. Tapping the button presents the same
/// "this year's periods + View all periods" list in a sheet; selecting one
/// calls back into `BudgetDetailViewModel.selectPeriod(id:)`.
struct TransactionsPeriodControl: View {
    let currentPeriod: Wellspent_V1_BudgetPeriod?
    let periods: [Wellspent_V1_BudgetPeriod]
    let profile: Wellspent_V1_BudgetProfile
    let localeIdentifier: String
    let onSelect: (String) -> Void

    @State private var isPresented = false

    private var periodsThisYear: [Wellspent_V1_BudgetPeriod] {
        guard let currentPeriod else { return [] }
        return PeriodGrouping.periodsInSameYear(as: currentPeriod, from: periods)
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(currentPeriod.map { PeriodGrouping.label(for: $0, localeIdentifier: localeIdentifier) } ?? "")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityIdentifier("transactionsPeriodControl")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                List {
                    ForEach(periodsThisYear, id: \.id) { period in
                        Button {
                            onSelect(period.id)
                            isPresented = false
                        } label: {
                            HStack {
                                Text(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if period.id == currentPeriod?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                } else if period.isArchived {
                                    Text("Archived")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("periodControlRow_\(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))")
                    }

                    NavigationLink {
                        PeriodListView(
                            profile: profile,
                            periods: periods,
                            localeIdentifier: localeIdentifier,
                            onSelect: { id in
                                onSelect(id)
                                isPresented = false
                            }
                        )
                    } label: {
                        Label("View all periods", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("viewAllPeriodsLink")
                }
                .listStyle(.plain)
                .sheetChrome(Text("Period")) { isPresented = false }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    TransactionsPeriodControl(
        currentPeriod: .with {
            $0.id = "p1"
            $0.startDate = Google_Protobuf_Timestamp(dateOnly: Date())
        },
        periods: [],
        profile: .with {
            $0.id = "preview-budget"
            $0.name = "Household Budget"
        },
        localeIdentifier: "en",
        onSelect: { _ in }
    )
}
