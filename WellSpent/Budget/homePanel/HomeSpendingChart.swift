import Charts
import SwiftUI

/// The categories card's compact chart: one stacked bar, or a small donut
/// with a legend. Each category keeps its own colour.
struct HomeSpendingChart: View {
    let segments: [HomeOverviewCalculations.Segment]
    let chartType: ExpenseChartView.ChartType
    let centerText: String

    var body: some View {
        switch chartType {
        case .bar:
            stackedBar
        case .pie:
            donut
        }
    }

    private var stackedBar: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(segments, id: \.id) { segment in
                    Rectangle()
                        .fill(Color(hexString: segment.colorHex))
                        .frame(width: max((proxy.size.width - gaps) * segment.fraction, 0))
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(Text("Spending by category"))
        .accessibilityValue(Text(accessibilitySummary))
        .accessibilityIdentifier("homeSpendingBar")
    }

    private var donut: some View {
        HStack(spacing: 16) {
            Chart(segments, id: \.id) { segment in
                SectorMark(angle: .value("Share", segment.fraction), innerRadius: .ratio(0.62), angularInset: 1)
                    .foregroundStyle(Color(hexString: segment.colorHex))
            }
            .chartLegend(.hidden)
            .frame(width: 96, height: 96)
            .overlay {
                Text(centerText)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: 56)
            }
            .accessibilityLabel(Text("Spending by category"))
            .accessibilityValue(Text(accessibilitySummary))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(segments, id: \.id) { segment in
                    HStack(spacing: 6) {
                        ColorDotView(hex: segment.colorHex, diameter: 8)
                        Text(segment.name).lineLimit(1)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("homeSpendingDonut")
    }

    private var accessibilitySummary: String {
        segments.map { "\($0.name) \(Int(($0.fraction * 100).rounded()))%" }.joined(separator: ", ")
    }
}
