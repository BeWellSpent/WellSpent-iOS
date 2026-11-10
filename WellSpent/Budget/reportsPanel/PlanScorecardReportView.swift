import SwiftUI
import WellSpentAPI

/// How each recent period went against the plan it had (canvas "Reports" page,
/// Scorecard): a headline card with the range, streak and a status strip, a row
/// per period, and this period by category so far.
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

    // MARK: Headline

    private func hero(_ scorecard: ReportsRESTMapping.Scorecard) -> some View {
        HomeCard {
            HStack {
                Text("On plan").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                ReportRangePicker(viewModel: viewModel)
            }

            if scorecard.scoredCount == 0 {
                Text("Your first score arrives when this period closes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scorecardNoScore")
            } else {
                Text("\(scorecard.onPlanCount) of \(scorecard.scoredCount) periods")
                    .font(.title.bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("scorecardOnPlan")
                if scorecard.streak > 0 {
                    Label {
                        Text("\(scorecard.streak) in a row under plan")
                    } icon: {
                        Image(systemName: "flame.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("scorecardStreak")
                }
            }

            strip(scorecard)
                .padding(.top, 10)

            if !viewModel.isPro {
                ProUpsellNote()
                    .padding(.top, 6)
            }
        }
    }

    /// One square per period, oldest first, with its status icon and month.
    private func strip(_ scorecard: ReportsRESTMapping.Scorecard) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(scorecard.periods.enumerated()), id: \.element.id) { index, period in
                let look = Look(status(period))
                let isCurrent = index == scorecard.periods.count - 1
                VStack(spacing: 4) {
                    Image(systemName: look.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(look.fg)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(look.bg, in: RoundedRectangle(cornerRadius: 8))
                    Text(period.start.formatted(Date.FormatStyle().month(.abbreviated).locale(Locale(identifier: viewModel.localeIdentifier))))
                        .font(.caption2.weight(isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
            }
        }
        .accessibilityHidden(true)
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
        let status = status(period)
        let look = Look(status)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: look.icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(look.fg)
                .frame(width: 32, height: 32)
                .background(look.bg, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(period.start.formatted(Date.FormatStyle().month(.wide).year().locale(Locale(identifier: viewModel.localeIdentifier))))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    look.label
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(look.fg)
                }
                details(period, status: status)
                    .font(.footnote)
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

    private func status(_ period: ReportsRESTMapping.ScorecardPeriod) -> ReportsCalculations.ScorecardStatus {
        ReportsCalculations.scorecardStatus(locked: period.locked, inProgress: period.inProgress, planRecorded: period.planRecorded, onPlan: period.onPlan)
    }

    /// Icon, colours and label for a status, shared by the strip and the rows.
    private struct Look {
        let icon: String
        let fg: Color
        let bg: Color
        let label: Text

        init(_ status: ReportsCalculations.ScorecardStatus) {
            switch status {
            case .onPlan: (icon, fg, label) = ("checkmark", .green, Text("On plan"))
            case .over: (icon, fg, label) = ("xmark", .red, Text("Over plan"))
            case .inProgress: (icon, fg, label) = ("clock", .accentColor, Text("In progress"))
            case .noPlan: (icon, fg, label) = ("minus", .secondary, Text("No plan"))
            case .notScored: (icon, fg, label) = ("minus", .secondary, Text("Nothing planned"))
            case .locked: (icon, fg, label) = ("lock.fill", Color(.tertiaryLabel), Text("Pro"))
            }
            bg = switch status {
            case .onPlan, .over, .inProgress: fg.opacity(0.14)
            case .noPlan, .notScored, .locked: Color(.tertiarySystemFill)
            }
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
        let colorHex = viewModel.categoryColor(category.categoryID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ColorDotView(hex: colorHex, diameter: 10)
                Text(viewModel.categoryName(category.categoryID))
                Spacer()
                (hasPlan ? Text("\(format(category.actual)) of \(format(category.planned))") : Text("\(format(category.actual)) · not planned"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOver ? .red : .primary)
                    .monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if hasPlan {
                ProgressView(value: HomeOverviewCalculations.fraction(actual, of: planned))
                    .tint(isOver ? .red : Color(hexString: colorHex))
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
