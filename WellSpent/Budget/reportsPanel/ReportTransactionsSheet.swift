import SwiftUI
import WellSpentAPI

/// Which rows a report element stands for.
struct ReportDrillDown: Identifiable {
    let periodID: String
    let categoryID: Int32

    var id: String { "\(periodID)-\(categoryID)" }
}

/// The transactions behind a report row — the "so what do I do about it" step.
struct ReportTransactionsSheet: View {
    let drillDown: ReportDrillDown
    let viewModel: ReportsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [Wellspent_V1_Transaction]?

    var body: some View {
        NavigationStack {
            List {
                if let transactions {
                    if transactions.isEmpty {
                        Text("No transactions.").foregroundStyle(.secondary)
                    }
                    ForEach(transactions, id: \.id) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transaction.name)
                                Text(transaction.date.dateOnly.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(TransactionAmountFormatting.displayText(
                                units: transaction.amount.units, nanos: transaction.amount.nanos,
                                currencyCode: viewModel.currencyCode, localeIdentifier: viewModel.localeIdentifier
                            ))
                            .monospacedDigit()
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text(viewModel.categoryName(drillDown.categoryID)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
            }
            .task {
                transactions = await viewModel.transactions(periodID: drillDown.periodID, categoryID: drillDown.categoryID)
            }
        }
        .accessibilityIdentifier("reportTransactionsSheet")
    }
}
