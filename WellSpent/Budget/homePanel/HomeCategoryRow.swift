import SwiftUI
import WellSpentAPI

/// One category: spent against planned with a bar in its own colour (red when
/// over). Tapping it opens each person's transactions under their name, the
/// drill-down the old Overview list had (issue #62).
struct HomeCategoryRow: View {
    let category: Wellspent_V1_Category
    let viewModel: ExpenseOverviewViewModel
    let currencyCode: String
    let localeIdentifier: String

    @State private var isExpanded = false

    var body: some View {
        let actual = viewModel.actualTotal(for: category)
        let planned = viewModel.plannedTotal(for: category)
        let isOver = viewModel.isOver(for: category)

        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ColorDotView(hex: category.color, diameter: 10)
                        Text(category.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        amounts(actual: actual, planned: planned, isOver: isOver)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    ProgressView(value: HomeOverviewCalculations.fraction(actual, of: planned))
                        .tint(isOver ? .red : (category.color.isEmpty ? .accentColor : Color(hexString: category.color)))
                        .padding(.leading, 20)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                breakdown
                    .padding(.leading, 20)
                    .padding(.bottom, 8)
            }
        }
        .accessibilityIdentifier("overviewCategoryRow_\(category.name)")
    }

    private func amounts(actual: (units: Int64, nanos: Int32), planned: (units: Int64, nanos: Int32), isOver: Bool) -> some View {
        // Money in stays +$X green, as everywhere; over is red. Within plan stays
        // plain: the bar beside it already says so.
        let tone = OverviewAmountFormatting.tone(actual: actual, planned: planned, isOver: isOver)
        let color: Color = tone == .received ? .green : (tone == .over ? .red : .primary)
        return HStack(spacing: 0) {
            Text(OverviewAmountFormatting.text(actual, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                .fontWeight(.semibold)
                .foregroundStyle(color)
            if !HomeOverviewCalculations.isZero(planned) {
                Text(verbatim: " / \(format(planned))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .monospacedDigit()
    }

    @ViewBuilder
    private var breakdown: some View {
        let groups = viewModel.transactionGroups(for: category)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.people, id: \.id) { person in
                let transactions = groups.byPerson[person.id] ?? []
                let actual = viewModel.actualTotal(for: category, person: person)
                if !transactions.isEmpty || !HomeOverviewCalculations.isZero(actual) {
                    HStack {
                        ColorDotView(hex: person.color, diameter: 8)
                        Text(person.userName)
                        Spacer()
                        Text(OverviewAmountFormatting.text(actual, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("overviewPersonRow_\(category.name)_\(person.userName)")
                    transactionList(transactions, owner: person.userName)
                }
            }
            // Spending that belongs to nobody (cash, or a method with no person).
            if !groups.unclaimed.isEmpty {
                Text("Unattributed")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                transactionList(groups.unclaimed, owner: "unattributed")
            }
        }
    }

    @ViewBuilder
    private func transactionList(_ transactions: [Wellspent_V1_Transaction], owner: String) -> some View {
        if !transactions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(transactions, id: \.id) { transaction in
                    HStack {
                        Text(transaction.name)
                        Spacer()
                        Text(transaction.date.dateOnly.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.tertiary)
                        // Signed like the Transactions tab: -$X out, +$X in.
                        Text(TransactionAmountFormatting.displayText(
                            units: transaction.amount.units, nanos: transaction.amount.nanos,
                            currencyCode: currencyCode, localeIdentifier: localeIdentifier
                        ))
                        .foregroundStyle(TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos) ? .green : .secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(.leading, 14)
            .accessibilityIdentifier("overviewTransactionList_\(category.name)_\(owner)")
        }
    }

    private func format(_ amount: (units: Int64, nanos: Int32)) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
