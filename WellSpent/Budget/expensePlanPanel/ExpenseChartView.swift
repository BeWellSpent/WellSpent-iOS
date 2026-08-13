import Charts
import SwiftUI

/// Shared pie/bar chart for the Expense Plan and Expense Overview tabs —
/// mirrors web's `ExpenseChart.tsx`: a segmented pie/bar toggle, each slice
/// or bar colored by the category's own color (or a fallback palette entry
/// — see `ExpenseChartCalculations`), with a colored legend under the pie
/// showing name/amount/percentage. Deliberately doesn't mirror web's
/// separate category/person grouping toggle — that wasn't part of what was
/// reported missing, and would roughly double this view's scope.
///
/// Touching a slice or a bar reveals its name, amount and percentage
/// (issue #39): the pie fills its own hollow center, the bar gets a card
/// anchored above it. Everything else dims so the selection reads clearly.
struct ExpenseChartView: View {
    enum ChartType: String, CaseIterable {
        case pie
        case bar
    }

    /// Past this many bars the x-axis category labels overlap into an
    /// unreadable smear — the complaint behind issue #39 — so they're hidden
    /// and the tooltip becomes the way to read a name. Unreadable text is
    /// worse than no text.
    private static let maxReadableBarLabels = 6

    let data: [ExpenseChartCalculations.Datum]
    @Binding var chartType: ChartType
    let currencyCode: String
    let localeIdentifier: String

    /// Swift Charts reports a pie selection as a position along the
    /// accumulated value scale and a bar selection as its x value, so the two
    /// charts can't share one selection binding.
    @State private var selectedAngle: Double?
    @State private var selectedBarName: String?

    private var total: Double {
        data.reduce(0) { $0 + $1.value }
    }

    private var selectedDatum: ExpenseChartCalculations.Datum? {
        switch chartType {
        case .pie:
            selectedAngle.flatMap { ExpenseChartCalculations.datum(atAngleValue: $0, in: data) }
        case .bar:
            selectedBarName.flatMap { name in data.first { $0.name == name } }
        }
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
        .onChange(of: chartType) { _, _ in clearSelection() }
        // A reload can reorder or drop categories entirely; a selection kept
        // across one would point at whatever now sits in that position.
        .onChange(of: data) { _, _ in clearSelection() }
    }

    private var pieChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(data) { datum in
                SectorMark(angle: .value("Value", datum.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(Color(hexString: datum.colorHex))
                    .cornerRadius(3)
                    .opacity(isDimmed(datum) ? 0.3 : 1)
            }
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        pieCenter
                            // The ring is drawn to the shorter dimension, so
                            // that's what the hole's size follows.
                            .frame(width: min(frame.width, frame.height) * 0.55)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 200)
            .accessibilityIdentifier("expensePieChart")

            legend
        }
    }

    @ViewBuilder
    private var pieCenter: some View {
        if let datum = selectedDatum {
            VStack(spacing: 2) {
                Text(datum.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text(amountText(datum.value))
                    .font(.caption2)
                Text(percentText(datum.value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .accessibilityIdentifier("expenseChartTooltip")
        } else {
            Text("Tap a slice for details")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var barChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart(data) { datum in
                BarMark(x: .value("Category", datum.name), y: .value("Amount", datum.value))
                    .foregroundStyle(Color(hexString: datum.colorHex))
                    .opacity(isDimmed(datum) ? 0.3 : 1)
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        if selectedBarName == datum.name {
                            tooltipCard(for: datum)
                        }
                    }
            }
            .chartXSelection(value: $selectedBarName)
            .chartXAxis(data.count > Self.maxReadableBarLabels ? .hidden : .automatic)
            .frame(height: 220)
            .accessibilityIdentifier("expenseBarChart")

            // Always laid out, so selecting a bar doesn't resize the row.
            Text("Tap a bar for details")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(selectedDatum == nil ? 1 : 0)
        }
    }

    private func tooltipCard(for datum: ExpenseChartCalculations.Datum) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(datum.name)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(amountText(datum.value))
                Text(percentText(datum.value))
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        )
        .accessibilityIdentifier("expenseChartTooltip")
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
                        Text(percentText(datum.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedDatum?.id == datum.id ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .accessibilityIdentifier("expenseChartLegendRow_\(datum.id)")
            }
        }
    }

    private func isDimmed(_ datum: ExpenseChartCalculations.Datum) -> Bool {
        guard let selectedDatum else { return false }
        return selectedDatum.id != datum.id
    }

    private func clearSelection() {
        selectedAngle = nil
        selectedBarName = nil
    }

    private func amountText(_ value: Double) -> String {
        let units = Int64(value.rounded(.towardZero))
        let nanos = Int32(((value - Double(units)) * 1_000_000_000).rounded())
        return MoneyFormatting.format(units: units, nanos: nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", ExpenseChartCalculations.percentage(of: value, total: total))
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
