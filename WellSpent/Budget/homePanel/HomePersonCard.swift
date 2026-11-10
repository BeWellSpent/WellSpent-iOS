import SwiftUI
import WellSpentAPI

/// One person's period: what they spent (savings included) against their
/// plan, then how much of it was saved and how much income arrived.
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
        let remaining = Calc.remaining(spent: spent, planned: planned)

        HomeCard {
            HStack(spacing: 8) {
                avatar
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
                let plannedText = format(planned)
                line(
                    isOver
                        ? Text("\(format(remaining)) over \(plannedText)")
                        : Text("\(format(remaining)) left of \(plannedText)"),
                    systemImage: isOver ? "exclamationmark" : "wallet.bifold",
                    status: isOver ? .over : .neutral
                )
                .accessibilityIdentifier("homePersonLeft_\(person.userName)")

                let saved = TransactionAmountFormatting.tuple(from: summary.savedActual)
                let savedPlanned = TransactionAmountFormatting.tuple(from: summary.savedPlanned)
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

    private var avatar: some View {
        let tint = person.color.isEmpty ? Color.accentColor : Color(hexString: person.color)
        return Text(String(person.userName.prefix(1)).uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
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
