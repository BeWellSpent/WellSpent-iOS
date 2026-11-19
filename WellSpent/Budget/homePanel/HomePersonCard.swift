import SwiftUI
import WellSpentAPI

/// One person's period: the total they spent (savings included), then that
/// total split into other spending, planned (fixed) paid and to pay, savings
/// against planned savings, and the income that arrived.
struct HomePersonCard: View {
    let person: Wellspent_V1_BudgetPerson
    let summary: BudgetRESTMapping.PersonPeriodSummary
    let currencyCode: String
    let localeIdentifier: String

    private typealias Calc = HomeOverviewCalculations

    var body: some View {
        let spent = TransactionAmountFormatting.tuple(from: summary.spentActual)
        let planned = TransactionAmountFormatting.tuple(from: summary.spentPlanned)
        let isOver = Calc.isOver(spent: spent, planned: planned)
        let saved = TransactionAmountFormatting.tuple(from: summary.savedActual)
        let savedPlanned = TransactionAmountFormatting.tuple(from: summary.savedPlanned)
        // Older servers lack the without-savings figures; derive them until every server sends them.
        let expenses = summary.expensesActual.map(TransactionAmountFormatting.tuple(from:)) ?? Calc.remaining(spent: saved, planned: spent)
        let expensesPlanned = summary.plannedExpenses.map(TransactionAmountFormatting.tuple(from:)) ?? Calc.remaining(spent: savedPlanned, planned: planned)
        let expensesOver = Calc.isOver(spent: expenses, planned: expensesPlanned)

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
                .tint(isOver ? .red : .accentColor)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                if let otherSpent = summary.otherSpent, let fixedPaid = summary.fixedPaid,
                   let fixedToPay = summary.fixedToPay, let fixedTotal = summary.fixedTotal {
                    line(Text("\(format(TransactionAmountFormatting.tuple(from: otherSpent))) other spending"), systemImage: "cart", status: .neutral)
                        .accessibilityIdentifier("homePersonUnplanned_\(person.userName)")
                    plannedLine(paid: fixedPaid, toPay: fixedToPay, total: fixedTotal)
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

                let income = TransactionAmountFormatting.tuple(from: summary.incomeActual)
                let incomePlanned = TransactionAmountFormatting.tuple(from: summary.incomePlanned)
                let incomeStatus = Calc.incomeStatus(received: income, planned: incomePlanned)
                line(
                    Text("\(format(income)) income of \(format(incomePlanned))"),
                    systemImage: incomeStatus == .met ? "checkmark" : "arrow.down",
                    status: incomeStatus
                )
                .accessibilityIdentifier("homePersonIncome_\(person.userName)")
            }
            .font(.subheadline)
            .monospacedDigit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homePersonCard_\(person.userName)")
    }

    /// Fixed transactions: paid of the total, and what's still to pay. Hidden when the person has none.
    @ViewBuilder
    private func plannedLine(paid: Wellspent_V1_Money, toPay: Wellspent_V1_Money, total: Wellspent_V1_Money) -> some View {
        let total = TransactionAmountFormatting.tuple(from: total)
        let toPay = TransactionAmountFormatting.tuple(from: toPay)
        let paid = format(TransactionAmountFormatting.tuple(from: paid))
        if total != (units: 0, nanos: 0) {
            let isDone = toPay == (units: 0, nanos: 0)
            line(
                isDone ? Text("\(paid) of \(format(total)) planned paid") : Text("\(paid) of \(format(total)) planned paid · \(format(toPay)) to pay"),
                systemImage: isDone ? "checkmark" : "calendar",
                status: isDone ? .met : .neutral
            )
            .accessibilityIdentifier("homePersonPlanned_\(person.userName)")
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

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        let magnitude = (units: abs(amount.units), nanos: abs(amount.nanos))
        return MoneyFormatting.format(units: magnitude.units, nanos: magnitude.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
