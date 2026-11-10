import SwiftUI
import WellSpentAPI

/// How each recent period went against the plan it had: a headline count and
/// streak, one row per period, and this period by category so far.
struct PlanScorecardReportView: View {
    let viewModel: ReportsViewModel

    @State private var drillDown: ReportDrillDown?

    var body: some View {
        if let scorecard = viewModel.scorecard {
            VStack(alignment: .leading, spacing: 10) {
                hero(scorecard)

                HomeSectionHeader(title: Text("Periods"))
                periods(scorecard)

                if !scorecard.current.isEmpty {
                    HomeSectionHeader(title: Text("This period so far"))
                    current(scorecard)
                }
            }
            .sheet(item: $drillDown) { ReportTransactionsSheet(drillDown: $0, viewModel: viewModel) }
        } else if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    // MARK: Hero

    private func hero(_ scorecard: ReportsRESTMapping.Scorecard) -> some View {
        HomeCard {
            Text("On plan").font(.caption).foregroundStyle(.secondary)
            if scorecard.scoredCount == 0 {
                Text("Your first score arrives when this period closes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scorecardNoScore")
            } else {
                Text("\(scorecard.onPlanCount) of \(scorecard.scoredCount) periods")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("scorecardOnPlan")
                if scorecard.streak > 0 {
                    Label {
                        Text("\(scorecard.streak) in a row under plan")
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("scorecardStreak")
                }
            }
            ReportRangePicker(viewModel: viewModel)
                .padding(.top, 4)
            if !viewModel.isPro {
                ProLockedNote(message: Text("Older periods and 6 or 12 period ranges are Pro."))
            }
        }
    }

    // MARK: Periods

    private func periods(_ scorecard: ReportsRESTMapping.Scorecard) -> some View {
        HomeCard {
            ForEach(Array(scorecard.periods.reversed().enumerated()), id: \.element.id) { index, period in
                if index > 0 { Divider() }
                periodRow(period)
            }
        }
        .accessibilityIdentifier("scorecardPeriods")
    }

    private func periodRow(_ period: ReportsRESTMapping.ScorecardPeriod) -> some View {
        let status = ReportsCalculations.scorecardStatus(locked: period.locked, inProgress: period.inProgress, planRecorded: period.planRecorded, onPlan: period.onPlan)
        return HStack(alignment: .top, spacing: 12) {
            statusIcon(status)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(period.start.formatted(Date.FormatStyle().month(.wide).year().locale(Locale(identifier: viewModel.localeIdentifier))))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    statusText(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint(status))
                }
                details(period, status: status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scorecardPeriod_\(period.id)")
    }

    @ViewBuilder
    private func details(_ period: ReportsRESTMapping.ScorecardPeriod, status: ReportsCalculations.ScorecardStatus) -> some View {
        switch status {
        case .locked:
            Text("Pro is coming soon")
        case .noPlan:
            if let actual = period.actualSpending {
                Text("\(format(actual)) spent · no plan recorded")
            }
        default:
            if let actual = period.actualSpending, let planned = period.plannedSpending {
                Text("\(format(actual)) spent of \(format(planned))")
            }
            if let within = period.categoriesWithin, let planned = period.categoriesPlanned, planned > 0 {
                Text("\(within) of \(planned) categories within plan")
            }
            if let saved = period.savingsActual, let target = period.savingsPlanned, HomeOverviewCalculations.decimal(TransactionAmountFormatting.tuple(from: target)) > 0 {
                Text("\(format(saved)) saved of \(format(target))")
                    .foregroundStyle(period.savingsMet == false ? Color.orange : .secondary)
            }
        }
    }

    private func statusIcon(_ status: ReportsCalculations.ScorecardStatus) -> some View {
        let name = switch status {
        case .onPlan: "checkmark"
        case .over: "xmark"
        case .inProgress: "clock"
        case .locked: "lock.fill"
        case .noPlan, .notScored: "minus"
        }
        return Image(systemName: name)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint(status))
            .frame(width: 32, height: 32)
            .background(tint(status).opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }

    private func statusText(_ status: ReportsCalculations.ScorecardStatus) -> Text {
        switch status {
        case .onPlan: Text("On plan")
        case .over: Text("Over plan")
        case .inProgress: Text("In progress")
        case .locked: Text("Pro")
        case .noPlan: Text("No plan")
        case .notScored: Text("Nothing planned")
        }
    }

    private func tint(_ status: ReportsCalculations.ScorecardStatus) -> Color {
        switch status {
        case .onPlan: .green
        case .over: .red
        case .inProgress: .accentColor
        case .locked, .noPlan, .notScored: .secondary
        }
    }

    // MARK: This period

    private func current(_ scorecard: ReportsRESTMapping.Scorecard) -> some View {
        HomeCard {
            ForEach(Array(scorecard.current.enumerated()), id: \.element.categoryID) { index, category in
                if index > 0 { Divider() }
                Button {
                    if let periodID = scorecard.periods.last?.id {
                        drillDown = ReportDrillDown(periodID: periodID, categoryID: category.categoryID)
                    }
                } label: {
                    categoryRow(category)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scorecardCategory_\(category.categoryID)")
            }
        }
    }

    private func categoryRow(_ category: ReportsRESTMapping.ScorecardCategory) -> some View {
        let actual = TransactionAmountFormatting.tuple(from: category.actual)
        let planned = TransactionAmountFormatting.tuple(from: category.planned)
        let hasPlan = HomeOverviewCalculations.decimal(planned) > 0
        let isOver = hasPlan && HomeOverviewCalculations.isOver(spent: actual, planned: planned)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ColorDotView(hex: viewModel.categoryColor(category.categoryID), diameter: 10)
                Text(viewModel.categoryName(category.categoryID))
                Spacer()
                (hasPlan ? Text("\(format(category.actual)) of \(format(category.planned))") : Text("\(format(category.actual)) · not planned"))
                    .font(.subheadline)
                    .foregroundStyle(isOver ? .red : .secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if hasPlan {
                ProgressView(value: HomeOverviewCalculations.fraction(actual, of: planned))
                    .tint(isOver ? .red : Color(hexString: viewModel.categoryColor(category.categoryID)))
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func format(_ money: Wellspent_V1_Money) -> String {
        MoneyFormatting.format(units: money.units, nanos: money.nanos, currencyCode: viewModel.currencyCode, localeIdentifier: viewModel.localeIdentifier)
    }
}
