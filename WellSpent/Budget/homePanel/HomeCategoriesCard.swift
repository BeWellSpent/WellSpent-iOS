import SwiftUI
import WellSpentAPI

/// Spending by category, kept compact: a small chart, a line naming every
/// category over its plan, the top 3 by spending, and "Show all" to expand
/// in place. Chart style lives in the card's "…" menu instead of its own row.
struct HomeCategoriesCard: View {
    let viewModel: ExpenseOverviewViewModel
    let currencyCode: String
    let localeIdentifier: String

    @State private var isExpanded = false

    var body: some View {
        let categories = viewModel.visibleCategories
        let otherName = String(localized: "Other", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        let segments = viewModel.chartSegments(otherName: otherName)

        HomeCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(format(viewModel.categoriesSpent)) of \(format(viewModel.categoriesPlanned))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("homeCategoriesTotals")
                Spacer()
                chartMenu
            }

            if !segments.isEmpty {
                HomeSpendingChart(segments: segments, chartType: viewModel.chartType, centerText: format(viewModel.categoriesSpent))
            }

            if !viewModel.overCategories.isEmpty {
                overPlanLine(viewModel.overCategories)
            }

            if categories.isEmpty {
                Text(viewModel.isLoading ? "" : String(localized: "No spending yet this period.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(HomeOverviewCalculations.visibleRows(categories, expanded: isExpanded).enumerated()), id: \.element.id) { index, category in
                        if index > 0 { Divider() }
                        HomeCategoryRow(category: category, viewModel: viewModel, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
                    }
                }
            }

            let uncategorized = viewModel.uncategorizedTotal
            if !HomeOverviewCalculations.isZero(uncategorized) {
                // Orange: uncategorized spend is something to go and fix.
                LabeledContent {
                    Text(OverviewAmountFormatting.text(uncategorized, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                } label: {
                    Text("Uncategorized").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityIdentifier("overviewUncategorizedTotal")
            }

            if categories.count > HomeOverviewCalculations.topCategoryCount {
                Divider()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        isExpanded
                            ? Text("Show top \(HomeOverviewCalculations.topCategoryCount)")
                            : Text("Show all \(categories.count) categories")
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("homeCategoriesToggle")
            }
        }
    }

    private var chartMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { viewModel.chartType },
                set: { newValue in Task { await viewModel.setChartType(newValue) } }
            )) {
                Label("Bar", systemImage: "chart.bar.fill").tag(ExpenseChartView.ChartType.bar)
                Label("Pie", systemImage: "chart.pie.fill").tag(ExpenseChartView.ChartType.pie)
            } label: {
                Text("Chart style")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.vertical, -12)
        .padding(.trailing, -10)
        .accessibilityLabel(Text("Chart style"))
        .accessibilityIdentifier("homeChartStyleMenu")
    }

    /// Names every category over plan, including ones outside the top 3, so
    /// overspending never hides below the fold.
    private func overPlanLine(_ over: [Wellspent_V1_Category]) -> some View {
        let details = over.map { category in
            let actual = viewModel.actualTotal(for: category)
            let planned = viewModel.plannedTotal(for: category)
            let excess = HomeOverviewCalculations.remaining(spent: planned, planned: actual)
            return "\(category.displayName) +\(format(excess))"
        }.joined(separator: " · ")
        return Label {
            Text("\(over.count) over plan: \(details)")
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("homeOverPlan")
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
