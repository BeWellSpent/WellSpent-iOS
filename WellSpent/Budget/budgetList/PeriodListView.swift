import Foundation
import SwiftUI
import WellSpentAPI

/// Every period this budget has ever had, grouped by year — reached from the
/// ☰ menu's "View all periods".
///
/// This was the app's home screen until issue #60; the budget itself is home
/// now, and this is where the full history went. It is deliberately a plain
/// picker: it selects a period and hands the ID back, rather than pushing a
/// second `BudgetDetailView`. Pushing would leave two live copies of the same
/// budget on the stack, each with its own polling view models.
struct PeriodListView: View {
    let profile: Wellspent_V1_BudgetProfile
    let periods: [Wellspent_V1_BudgetPeriod]
    let localeIdentifier: String
    let onSelect: (String) -> Void

    @State private var selectedYear: Int?

    private var yearGroups: [PeriodYearGroup] { PeriodGrouping.groupByYear(periods) }
    private var years: [Int] { yearGroups.map(\.year) }

    private var effectiveYear: Int? {
        if let selectedYear, years.contains(selectedYear) { return selectedYear }
        return years.first
    }

    private var periodsForYear: [Wellspent_V1_BudgetPeriod] {
        yearGroups.first { $0.year == effectiveYear }?.periods ?? []
    }

    var body: some View {
        List {
            if years.isEmpty {
                Text("No periods yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    Picker("Year", selection: Binding(
                        get: { effectiveYear ?? years[0] },
                        set: { selectedYear = $0 }
                    )) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .accessibilityIdentifier("yearPicker")
                }

                Section {
                    ForEach(periodsForYear, id: \.id) { period in
                        Button {
                            onSelect(period.id)
                        } label: {
                            periodRow(period)
                        }
                        .accessibilityIdentifier("periodRow_\(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func periodRow(_ period: Wellspent_V1_BudgetPeriod) -> some View {
        HStack {
            Text(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))
                .foregroundStyle(.primary)
            Spacer()
            (period.isArchived ? Text("Archived") : Text("Active"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(period.isArchived ? Color.gray.opacity(0.2) : Color.green.opacity(0.2))
                .foregroundStyle(period.isArchived ? Color.secondary : Color.green)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    NavigationStack {
        PeriodListView(
            profile: .with {
                $0.id = "preview-budget"
                $0.name = "Household Budget"
            },
            periods: [
                .with {
                    $0.id = "p1"
                    $0.startDate = Google_Protobuf_Timestamp(dateOnly: Date())
                    $0.endDate = Google_Protobuf_Timestamp(dateOnly: Date())
                },
                .with {
                    $0.id = "p2"
                    $0.isArchived = true
                    $0.startDate = Google_Protobuf_Timestamp(dateOnly: Date().addingTimeInterval(-60 * 60 * 24 * 40))
                    $0.endDate = Google_Protobuf_Timestamp(dateOnly: Date().addingTimeInterval(-60 * 60 * 24 * 10))
                },
            ],
            localeIdentifier: "en",
            onSelect: { _ in }
        )
    }
}
