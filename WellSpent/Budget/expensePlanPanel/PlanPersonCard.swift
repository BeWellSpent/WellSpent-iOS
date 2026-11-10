import SwiftUI
import WellSpentAPI

/// One person's plan: what they plan to spend (savings included), and how
/// their planned income splits into expenses, savings and what remains.
struct PlanPersonCard: View {
    let person: Wellspent_V1_BudgetPerson
    let summary: BudgetRESTMapping.PersonPeriodSummary
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        let planned = TransactionAmountFormatting.tuple(from: summary.spentPlanned)
        let savings = TransactionAmountFormatting.tuple(from: summary.savedPlanned)
        let income = TransactionAmountFormatting.tuple(from: summary.incomePlanned)
        let expenses = summary.plannedExpenses.map { TransactionAmountFormatting.tuple(from: $0) }
        let remaining = summary.plannedRemaining.map { TransactionAmountFormatting.tuple(from: $0) }

        HomeCard {
            HStack(spacing: 8) {
                PersonAvatar(person: person)
                Text(person.userName)
                    .font(.subheadline.weight(.semibold))
            }

            Text("Planned this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(format(planned))
                .font(.title2.bold())
                .monospacedDigit()
                .accessibilityIdentifier("planPersonPlanned_\(person.userName)")
            splitBar(
                expenses: expenses.map { HomeOverviewCalculations.fraction($0, of: income) } ?? 0,
                savings: HomeOverviewCalculations.fraction(savings, of: income)
            )
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                if let expenses {
                    line(Text("\(format(expenses)) expenses"), dot: .accentColor)
                }
                line(Text("\(format(savings)) savings"), dot: .green)
                if let remaining {
                    let over = MoneyFormatting.isNegative(units: remaining.units, nanos: remaining.nanos)
                    line(Text("\(format(remaining)) remaining of \(format(income)) income"), dot: Color(.systemGray3))
                        .foregroundStyle(over ? .red : .primary)
                        .accessibilityIdentifier("planPersonRemaining_\(person.userName)")
                }
            }
            .font(.subheadline)
            .monospacedDigit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planPersonCard_\(person.userName)")
    }

    private func line(_ text: Text, dot: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 10, height: 10).padding(.horizontal, 7).accessibilityHidden(true)
            text
        }
    }

    /// Their income split into planned expenses and savings; the empty track is what remains.
    private func splitBar(expenses: Double, savings: Double) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Rectangle().fill(Color.accentColor).frame(width: proxy.size.width * expenses)
                Rectangle().fill(Color.green).frame(width: proxy.size.width * savings)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}

/// A person's initial in their own colour.
struct PersonAvatar: View {
    let person: Wellspent_V1_BudgetPerson

    var body: some View {
        let tint = person.color.isEmpty ? Color.accentColor : Color(hexString: person.color)
        Text(String(person.userName.prefix(1)).uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}
