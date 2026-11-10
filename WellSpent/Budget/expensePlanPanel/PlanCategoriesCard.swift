import SwiftUI
import WellSpentAPI

/// The Plan's categories, kept compact like Home's: a small chart of planned
/// amounts, a legend for the fixed/other split, a line for categories whose
/// fixed bills exceed the manual amount, the top 3 and "Show all".
struct PlanCategoriesCard: View {
    let viewModel: ExpensePlanViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onAllocate: (Wellspent_V1_Category) -> Void

    @State private var isExpanded = false

    var body: some View {
        let categories = viewModel.visibleCategories
        let otherName = String(localized: "Other", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        let segments = viewModel.chartSegments(otherName: otherName)

        HomeCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(categories.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                chartMenu
            }

            if !segments.isEmpty {
                HomeSpendingChart(segments: segments, chartType: viewModel.chartType, centerText: format(viewModel.committedIncludingSavingsTotal))
            }

            legend

            let over = viewModel.fixedOverManualCategories
            if !over.isEmpty {
                fixedOverManualLine(over)
            }

            if categories.isEmpty {
                Text(viewModel.isLoading ? "" : String(localized: "No categories planned yet. Tap + to add one.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(HomeOverviewCalculations.visibleRows(categories, expanded: isExpanded).enumerated()), id: \.element.id) { index, category in
                        if index > 0 { Divider() }
                        PlanCategoryRow(category: category, viewModel: viewModel, currencyCode: currencyCode, localeIdentifier: localeIdentifier, canEdit: canEdit) {
                            onAllocate(category)
                        }
                    }
                }
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
                .accessibilityIdentifier("planCategoriesToggle")
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Text("Fixed"), color: Color(.systemGray))
            legendItem(Text("Other spending"), color: Color(.systemGray4))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ label: Text, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 6)
            label
        }
    }

    private var chartMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { viewModel.chartType },
                set: { newValue in Task { await viewModel.setChartType(newValue) } }
            )) {
                Label("Bar", systemImage: "chart.bar.fill").tag(ExpenseChartType.bar)
                Label("Pie", systemImage: "chart.pie.fill").tag(ExpenseChartType.pie)
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
        .accessibilityIdentifier("planChartStyleMenu")
    }

    /// Orange, not red: nothing is overspent yet, the plan just doesn't cover the bills.
    private func fixedOverManualLine(_ over: [Wellspent_V1_Category]) -> some View {
        let details = over.map { category in
            let excess = HomeOverviewCalculations.remaining(spent: viewModel.allocatedTotal(for: category), planned: viewModel.fixedDueTotal(for: category))
            return String(localized: "\(category.displayName): fixed bills are \(format(excess)) over the manual amount", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }.joined(separator: " · ")
        return Label {
            Text(details)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("planFixedOverManual")
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
