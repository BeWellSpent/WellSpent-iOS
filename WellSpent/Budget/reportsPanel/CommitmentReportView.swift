import SwiftUI
import WellSpentAPI

/// What the budget owes before spending anything: committed per period, what's
/// coming (Pro), the current period by category, and the payment plans.
struct CommitmentReportView: View {
    let viewModel: ReportsViewModel

    @State private var drillDown: ReportDrillDown?

    var body: some View {
        if let report = viewModel.commitments {
            VStack(alignment: .leading, spacing: 10) {
                hero(report)

                HomeSectionHeader(title: Text("Coming up"))
                comingUp(report)

                if !report.categories.isEmpty {
                    HomeSectionHeader(title: Text("By category"))
                    byCategory(report)
                }

                if !viewModel.plans.isEmpty {
                    HomeSectionHeader(title: Text("Payment plans"))
                    plans
                }
            }
            .sheet(item: $drillDown) { ReportTransactionsSheet(drillDown: $0, viewModel: viewModel) }
        } else if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func hero(_ report: ReportsRESTMapping.Commitments) -> some View {
        let current = report.periods.last?.amount.map { TransactionAmountFormatting.tuple(from: $0) } ?? (0, 0)
        return HomeCard {
            Text("Committed each period").font(.caption).foregroundStyle(.secondary)
            Text(format(current)).font(.title2.bold()).monospacedDigit()
                .accessibilityIdentifier("reportsCommitted")
            Text(heroSubtitle(report)).font(.caption).foregroundStyle(.secondary)
            PeriodBars(periods: report.periods, localeIdentifier: viewModel.localeIdentifier)
                .padding(.top, 8)
        }
    }

    private func heroSubtitle(_ report: ReportsRESTMapping.Commitments) -> String {
        var parts: [String] = []
        if let percent = report.committedPercentOfIncome {
            parts.append(String(localized: "\(ReportsCalculations.percentText(percent)) of income", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
        }
        parts.append(String(localized: "\(report.billCount) bills", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
        parts.append(String(localized: "\(report.planCount) payment plans", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func comingUp(_ report: ReportsRESTMapping.Commitments) -> some View {
        if report.projectionLocked {
            ProLockedNote(message: Text("See when your fixed costs go down"))
                .accessibilityIdentifier("reportsProjectionLocked")
        } else if let drops = report.projection, !drops.isEmpty {
            HomeCard {
                ForEach(Array(drops.enumerated()), id: \.offset) { index, drop in
                    if index > 0 { Divider() }
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .frame(width: 32, height: 32)
                            .background(Color.green.opacity(0.15), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drop.endsOn.formatted(Date.FormatStyle().month(.wide).year().locale(Locale(identifier: viewModel.localeIdentifier))))
                                .font(.subheadline.weight(.semibold))
                            Text(drop.names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("−\(format(TransactionAmountFormatting.tuple(from: drop.amount)))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("reportsProjection")
        } else {
            HomeCard {
                Text("No payment plans end in the next six months.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func byCategory(_ report: ReportsRESTMapping.Commitments) -> some View {
        let largest = report.categories.first.map { TransactionAmountFormatting.tuple(from: $0.amount) } ?? (0, 0)
        return HomeCard {
            ForEach(Array(report.categories.enumerated()), id: \.offset) { index, category in
                if index > 0 { Divider() }
                let amount = TransactionAmountFormatting.tuple(from: category.amount)
                Button {
                    if let periodID = report.periods.last?.id {
                        drillDown = ReportDrillDown(periodID: periodID, categoryID: category.categoryID, fixedOnly: true)
                    }
                } label: {
                    CategoryBarRow(
                        name: viewModel.categoryName(category.categoryID),
                        colorHex: viewModel.categoryColor(category.categoryID),
                        amountText: format(amount),
                        fraction: HomeOverviewCalculations.fraction(amount, of: largest)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reportsCommitCategory_\(category.categoryID)")
            }
        }
    }

    private var plans: some View {
        HomeCard {
            ForEach(Array(viewModel.plans.enumerated()), id: \.element.id) { index, plan in
                if index > 0 { Divider() }
                let soon = FixedExpensePlanSummary.isEndingSoon(plan)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(plan.name)
                        Spacer()
                        Text(format((plan.plannedAmount.units, plan.plannedAmount.nanos))).fontWeight(.semibold).monospacedDigit()
                    }
                    if plan.totalPayments > 0 {
                        ProgressView(value: Double(plan.paymentsMade), total: Double(plan.totalPayments))
                            .tint(soon ? .orange : .accentColor)
                    }
                    HStack(spacing: 4) {
                        if let progress = FixedExpensePlanSummary.progressText(for: plan) { Text(progress) }
                        if let ends = FixedExpensePlanSummary.endsText(for: plan, localeIdentifier: viewModel.localeIdentifier) {
                            Text("·")
                            Text(ends).foregroundStyle(soon ? .orange : .secondary).fontWeight(soon ? .semibold : .regular)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("reportsPlans")
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: viewModel.currencyCode, localeIdentifier: viewModel.localeIdentifier)
    }
}

/// One small bar per period, the current one highlighted; locked periods show a lock.
struct PeriodBars: View {
    let periods: [ReportsRESTMapping.Period]
    let localeIdentifier: String

    var body: some View {
        let fractions = ReportsCalculations.barFractions(periods.map { $0.amount.map { TransactionAmountFormatting.tuple(from: $0) } })
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(periods.enumerated()), id: \.offset) { index, period in
                let isCurrent = index == periods.count - 1
                VStack(spacing: 4) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(period.locked ? Color(.tertiarySystemFill) : (isCurrent ? Color.accentColor : Color.accentColor.opacity(0.3)))
                        if period.locked {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    }
                    .frame(height: max(80 * fractions[index], 4))
                    Text(period.start.formatted(Date.FormatStyle().month(.abbreviated).locale(Locale(identifier: localeIdentifier))))
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 100, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Name, amount and a bar in the category's colour; tapping opens the rows behind it.
struct CategoryBarRow: View {
    let name: String
    let colorHex: String
    let amountText: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ColorDotView(hex: colorHex, diameter: 10)
                Text(name)
                Spacer()
                Text(amountText).fontWeight(.semibold).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            ProgressView(value: fraction)
                .tint(Color(hexString: colorHex))
                .padding(.leading, 20)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
