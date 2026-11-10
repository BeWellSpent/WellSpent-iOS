import Charts
import SwiftUI
import WellSpentAPI

/// Spending per category across recent periods as stacked bars ($ or % of
/// income), and the biggest movers against the trailing 3-period average.
struct CategoryTrendsReportView: View {
    let viewModel: ReportsViewModel

    @State private var drillDown: ReportDrillDown?

    var body: some View {
        if let report = viewModel.trends {
            VStack(alignment: .leading, spacing: 10) {
                chartCard(report)

                HStack(alignment: .firstTextBaseline) {
                    HomeSectionHeader(title: Text("Biggest movers"))
                    Spacer()
                    Text("vs 3-period average").font(.caption).foregroundStyle(.secondary)
                }
                movers(report)
            }
            .sheet(item: $drillDown) { ReportTransactionsSheet(drillDown: $0, viewModel: viewModel) }
        } else if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func chartCard(_ report: ReportsRESTMapping.Trends) -> some View {
        HomeCard {
            HStack {
                rangePicker
                Spacer()
                Picker("Units", selection: Binding(get: { viewModel.showPercent }, set: { viewModel.showPercent = $0 })) {
                    Text(verbatim: "$").tag(false)
                    Text(verbatim: "%").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .accessibilityIdentifier("reportsUnitsPicker")
            }

            let ghost = ghostHeight(report)
            Chart {
                ForEach(report.periods, id: \.id) { period in
                    let label = monthLabel(period.start)
                    if period.locked {
                        // A locked period's amount is unknown: a ghost column at a share of the tallest real one.
                        BarMark(x: .value("Period", label), y: .value("Amount", ghost))
                            .foregroundStyle(Color(.tertiarySystemFill))
                            .annotation(position: .overlay, alignment: .top) {
                                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
                            }
                    } else {
                        ForEach(Array(period.categories.enumerated()), id: \.element.categoryID) { index, category in
                            let bar = BarMark(x: .value("Period", label), y: .value("Amount", value(category)))
                                .foregroundStyle(Color(hexString: viewModel.categoryColor(category.categoryID)))
                            if index == period.categories.count - 1 {
                                bar.annotation(position: .top) {
                                    Text(totalLabel(period)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                }
                            } else {
                                bar
                            }
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 180)
            .accessibilityLabel(Text("Spending by period"))

            legend(report)

            if !viewModel.isPro {
                ProLockedNote(message: Text("Older periods and 6 or 12 period ranges are Pro."))
            }
        }
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).locale(Locale(identifier: viewModel.localeIdentifier)))
    }

    /// 60% of the tallest unlocked column, in whichever unit is showing.
    private func ghostHeight(_ report: ReportsRESTMapping.Trends) -> Double {
        let tallest = report.periods.filter { !$0.locked }.map { $0.categories.reduce(0) { $0 + value($1) } }.max() ?? 0
        return tallest > 0 ? tallest * 0.6 : 1
    }

    /// The column's total above it: "$4.6k", or the share of that period's income.
    private func totalLabel(_ period: ReportsRESTMapping.Period) -> String {
        if viewModel.showPercent {
            return period.percentOfIncome.map(ReportsCalculations.percentText) ?? ""
        }
        guard let total = period.amount else { return "" }
        return ReportsCalculations.compactMoneyText(TransactionAmountFormatting.tuple(from: total), currencyCode: viewModel.currencyCode, localeIdentifier: viewModel.localeIdentifier)
    }

    /// Percent of income when that's on and known; locked bars get a placeholder height above.
    private func value(_ category: ReportsRESTMapping.CategoryAmount) -> Double {
        if viewModel.showPercent { return category.percentOfIncome ?? 0 }
        return NSDecimalNumber(decimal: HomeOverviewCalculations.decimal(TransactionAmountFormatting.tuple(from: category.amount))).doubleValue
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(ReportsCalculations.trendRanges, id: \.self) { range in
                let locked = ReportsCalculations.isRangeLocked(range, isPro: viewModel.isPro)
                Button {
                    Task { await viewModel.selectRange(range) }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(range) periods")
                        if locked { Image(systemName: "lock.fill").font(.caption2) }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.range == range ? Color.primary : Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(viewModel.range == range ? Color(.systemBackground) : (locked ? .secondary : .primary))
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .accessibilityIdentifier("reportsRange_\(range)")
            }
        }
    }

    private func legend(_ report: ReportsRESTMapping.Trends) -> some View {
        let ids = report.periods.last?.categories.map(\.categoryID) ?? []
        return FlowLegend(items: ids.prefix(6).map { (viewModel.categoryName($0), viewModel.categoryColor($0)) })
    }

    @ViewBuilder
    private func movers(_ report: ReportsRESTMapping.Trends) -> some View {
        if report.movers.isEmpty {
            HomeCard {
                Text("Trends appear once you have a few periods.").font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            HomeCard {
                ForEach(Array(report.movers.enumerated()), id: \.offset) { index, mover in
                    if index > 0 { Divider() }
                    Button {
                        if let periodID = report.periods.last?.id {
                            drillDown = ReportDrillDown(periodID: periodID, categoryID: mover.categoryID)
                        }
                    } label: {
                        moverRow(mover, currentMonth: report.periods.last.map { monthLabel($0.start) } ?? "")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reportsMover_\(mover.categoryID)")
                }
            }
        }
    }

    private func moverRow(_ mover: ReportsRESTMapping.Mover, currentMonth: String) -> some View {
        let delta = TransactionAmountFormatting.tuple(from: mover.delta)
        let up = ReportsCalculations.isIncrease(delta)
        let tint: Color = up ? .red : .green
        let deltaText: String = {
            if viewModel.showPercent, let percent = mover.deltaPercentOfIncome {
                return (up ? "+" : "") + ReportsCalculations.percentText(percent)
            }
            let magnitude = (abs(delta.units), abs(delta.nanos))
            return (up ? "+" : "−") + format(magnitude)
        }()
        return HStack(spacing: 12) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ColorDotView(hex: viewModel.categoryColor(mover.categoryID), diameter: 8)
                    Text(viewModel.categoryName(mover.categoryID))
                }
                Text("\(format(TransactionAmountFormatting.tuple(from: mover.current))) in \(currentMonth) · \(format(TransactionAmountFormatting.tuple(from: mover.average))) average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(deltaText).fontWeight(.bold).foregroundStyle(tint).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: viewModel.currencyCode, localeIdentifier: viewModel.localeIdentifier)
    }
}

/// A wrapping row of colour dots and names.
struct FlowLegend: View {
    let items: [(name: String, colorHex: String)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { entries }
            VStack(alignment: .leading, spacing: 4) { entries }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var entries: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack(spacing: 6) {
                ColorDotView(hex: item.colorHex, diameter: 8)
                Text(item.name).lineLimit(1)
            }
        }
    }
}
