import Charts
import SwiftUI

/// Shared pie/bar chart for the Expense Plan and Expense Overview tabs —
/// mirrors web's `ExpenseChart.tsx`: a segmented pie/bar toggle, each slice
/// or bar colored by the category's own color (or a fallback palette entry
/// — see `ExpenseChartCalculations`), with a colored legend under the pie
/// showing name/amount/percentage. Deliberately doesn't mirror web's
/// separate category/person grouping toggle — that wasn't part of what was
/// reported missing, and would roughly double this view's scope.
struct ExpenseChartView: View {
    enum ChartType: String, CaseIterable {
        case pie
        case bar
    }

    let data: [ExpenseChartCalculations.Datum]
    @Binding var chartType: ChartType
    let currencyCode: String
    let localeIdentifier: String

    private var total: Double {
        data.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Chart type", selection: $chartType) {
                Text("Pie").tag(ChartType.pie)
                Text("Bar").tag(ChartType.bar)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("expenseChartTypePicker")

            if data.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if chartType == .pie {
                pieChart
            } else {
                barChart
            }
        }
        .listRowSeparator(.hidden)
    }

    private var pieChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(data) { datum in
                SectorMark(angle: .value("Value", datum.value), innerRadius: .ratio(0.5), angularInset: 1.5)
                    .foregroundStyle(Color(hexString: datum.colorHex))
                    .cornerRadius(3)
            }
            .frame(height: 200)
            .accessibilityIdentifier("expensePieChart")

            legend
        }
    }

    private var barChart: some View {
        Chart(data) { datum in
            BarMark(x: .value("Category", datum.name), y: .value("Amount", datum.value))
                .foregroundStyle(Color(hexString: datum.colorHex))
        }
        .frame(height: 220)
        .accessibilityIdentifier("expenseBarChart")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(data) { datum in
                HStack(spacing: 6) {
                    ColorDotView(hex: datum.colorHex, diameter: 8)
                    Text(datum.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(amountText(datum.value))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if total > 0 {
                        Text(String(format: "%.1f%%", datum.value / total * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func amountText(_ value: Double) -> String {
        let units = Int64(value.rounded(.towardZero))
        let nanos = Int32(((value - Double(units)) * 1_000_000_000).rounded())
        return MoneyFormatting.format(units: units, nanos: nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}

#Preview {
    ExpenseChartView(
        data: [
            .init(id: 1, name: "Groceries", value: 400, colorHex: "#6366f1"),
            .init(id: 2, name: "Rent", value: 1500, colorHex: "#22c55e"),
            .init(id: 3, name: "Dining", value: 150, colorHex: "#f59e0b")
        ],
        chartType: .constant(.pie),
        currencyCode: "USD",
        localeIdentifier: "en"
    )
    .padding()
}
