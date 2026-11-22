import SwiftUI
import WellSpentAPI

/// One person's period: the total they spent (savings included), then the plan
/// used, what is still to pay, spending over or outside the plan, savings,
/// income, and whether the month can be finished or needs a transfer.
struct HomePersonCard: View {
    let person: Wellspent_V1_BudgetPerson
    let summary: BudgetRESTMapping.PersonPeriodSummary
    let currencyCode: String
    let localeIdentifier: String

    private typealias Calc = HomeOverviewCalculations
    private typealias Amount = (units: Int64, nanos: Int32)

    var body: some View {
        let spent = TransactionAmountFormatting.tuple(from: summary.spentActual)
        let planned = TransactionAmountFormatting.tuple(from: summary.spentPlanned)
        let saved = TransactionAmountFormatting.tuple(from: summary.savedActual)
        let savedPlanned = TransactionAmountFormatting.tuple(from: summary.savedPlanned)
        // Older servers lack the without-savings figures; derive them until every server sends them.
        let expenses = summary.expensesActual.map(TransactionAmountFormatting.tuple(from:)) ?? Calc.remaining(spent: saved, planned: spent)
        let expensesPlanned = summary.plannedExpenses.map(TransactionAmountFormatting.tuple(from:)) ?? Calc.remaining(spent: savedPlanned, planned: planned)
        let expensesOver = Calc.isOver(spent: expenses, planned: expensesPlanned)
        let left = summary.leftAfterBills.map(TransactionAmountFormatting.tuple(from:))
        let needsTransfer = left.map(isNegative) ?? false

        HomeCard {
            HStack(spacing: 8) {
                PersonAvatar(person: person)
                Text(person.userName)
                    .font(.subheadline.weight(.semibold))
            }

            Text("Spent this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(OverviewAmountFormatting.text(spent, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                .font(.title2.bold())
                .monospacedDigit()
                .accessibilityIdentifier("homePersonSpent_\(person.userName)")
            ProgressView(value: Calc.fraction(spent, of: planned))
                .tint(Calc.isOver(spent: spent, planned: planned) || needsTransfer ? .red : .accentColor)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                if let plannedSpent = summary.plannedSpent, let overPlan = summary.overPlan, let unplanned = summary.unplanned,
                   let toPay = summary.fixedToPay {
                    planLines(
                        used: TransactionAmountFormatting.tuple(from: plannedSpent), planned: expensesPlanned,
                        toPay: TransactionAmountFormatting.tuple(from: toPay),
                        overPlan: TransactionAmountFormatting.tuple(from: overPlan),
                        unplanned: TransactionAmountFormatting.tuple(from: unplanned)
                    )
                } else {
                    line(
                        Text("\(format(expenses)) spent of \(format(expensesPlanned))"),
                        systemImage: expensesOver ? "exclamationmark" : "cart",
                        status: expensesOver ? .over : .neutral
                    )
                    .accessibilityIdentifier("homePersonLeft_\(person.userName)")
                }

                let savedStatus = Calc.savedStatus(saved: saved, planned: savedPlanned)
                line(
                    Text("\(format(saved)) saved of \(format(savedPlanned))"),
                    systemImage: savedStatus == .met ? "checkmark" : "banknote",
                    status: savedStatus
                )
                .accessibilityIdentifier("homePersonSaved_\(person.userName)")

                if let savingsToPay = summary.savingsToPay.map(TransactionAmountFormatting.tuple(from:)), !isZero(savingsToPay) {
                    line(Text("\(format(savingsToPay)) savings still to transfer"), systemImage: "arrow.right", status: .short)
                        .accessibilityIdentifier("homePersonSavingsToPay_\(person.userName)")
                }

                let income = TransactionAmountFormatting.tuple(from: summary.incomeActual)
                let incomePlanned = TransactionAmountFormatting.tuple(from: summary.incomePlanned)
                let incomeStatus = Calc.incomeStatus(received: income, planned: incomePlanned)
                line(
                    Text("\(format(income)) income of \(format(incomePlanned))"),
                    systemImage: incomeStatus == .met ? "checkmark" : "arrow.down",
                    status: incomeStatus
                )
                .accessibilityIdentifier("homePersonIncome_\(person.userName)")

                if let left {
                    Divider()
                    Group {
                        if needsTransfer {
                            line(Text("Needs \(format(left)) to finish the month and savings"), systemImage: "exclamationmark", status: .over)
                        } else {
                            line(Text("\(format(left)) left after bills"), systemImage: "checkmark", status: .met)
                        }
                    }
                    .accessibilityIdentifier("homePersonLeftAfterBills_\(person.userName)")
                }
            }
            .font(.subheadline)
            .monospacedDigit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homePersonCard_\(person.userName)")
    }

    /// Plan used (capped per category on the server), bills still to pay, then spending over and outside the plan.
    @ViewBuilder
    private func planLines(used: Amount, planned: Amount, toPay: Amount, overPlan: Amount, unplanned: Amount) -> some View {
        if !isZero(planned) {
            line(Text("\(format(used)) of \(format(planned)) planned"), systemImage: "calendar", status: .neutral)
                .accessibilityIdentifier("homePersonPlanned_\(person.userName)")
            line(
                Text("\(format(toPay)) still to pay"),
                systemImage: isZero(toPay) ? "checkmark" : "hourglass",
                status: isZero(toPay) ? .met : .neutral
            )
            .accessibilityIdentifier("homePersonToPay_\(person.userName)")
        }
        if !isZero(overPlan) {
            line(Text("\(format(overPlan)) over plan"), systemImage: "exclamationmark", status: .over)
                .accessibilityIdentifier("homePersonOverPlan_\(person.userName)")
        }
        if !isZero(unplanned) {
            line(Text("\(format(unplanned)) unplanned"), systemImage: "plus", status: .neutral)
                .accessibilityIdentifier("homePersonUnplanned_\(person.userName)")
        }
    }

    private func line(_ text: Text, systemImage: String, status: HomeOverviewCalculations.LineStatus) -> some View {
        let tint: Color = switch status {
        case .met: .green
        case .short: .orange
        case .over: .red
        case .neutral: .secondary
        }
        return HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            text
                .foregroundStyle(status == .over ? .red : .primary)
        }
    }

    private func isZero(_ amount: Amount) -> Bool { amount == (units: 0, nanos: 0) }

    private func isNegative(_ amount: Amount) -> Bool { amount.units < 0 || amount.nanos < 0 }

    private func format(_ amount: Amount) -> String {
        let magnitude = (units: abs(amount.units), nanos: abs(amount.nanos))
        return MoneyFormatting.format(units: magnitude.units, nanos: magnitude.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
