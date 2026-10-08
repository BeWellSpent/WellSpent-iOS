import SwiftUI
import WellSpentAPI

struct MatchTransactionsSheet: View {
    let matchedTransaction: Wellspent_V1_Transaction
    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let authenticatedClient: ProtocolClient
    let onMatched: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MatchTransactionsViewModel?
    @State private var filter = ""

    private func filteredCandidates(_ viewModel: MatchTransactionsViewModel) -> [Wellspent_V1_Transaction] {
        guard !filter.isEmpty else { return viewModel.variableTransactions }
        return viewModel.variableTransactions.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .sheetChrome(Text("Match Transactions")) { dismiss() }
            .task {
                if viewModel == nil {
                    viewModel = MatchTransactionsViewModel(
                        budgetPeriodID: budgetPeriodID,
                        budgetProfileID: budgetProfileID,
                        authenticatedClient: authenticatedClient
                    )
                }
                await viewModel?.load()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: MatchTransactionsViewModel) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(matchedTransaction.name)
                    .font(.headline)
                Text("Planned: \(MoneyFormatting.format(units: matchedTransaction.plannedAmount.units, nanos: matchedTransaction.plannedAmount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            let candidates = filteredCandidates(viewModel)
            List {
                if viewModel.isLoading {
                    ProgressView()
                } else if candidates.isEmpty {
                    (filter.isEmpty ? Text("No variable transactions this period.") : Text("No matches."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates, id: \.id) { candidate in
                        candidateRow(candidate, viewModel: viewModel)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .searchable(text: $filter)

            if !viewModel.selectedIDs.isEmpty {
                let total = viewModel.selectedTotal
                let matches = viewModel.matchesExactly(matchedTransaction)
                let totalText = MoneyFormatting.format(units: total.units, nanos: total.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
                (matches ? Text("Selected: \(totalText)") : Text("Selected \(totalText) — must total \(MoneyFormatting.format(units: matchedTransaction.plannedAmount.units, nanos: matchedTransaction.plannedAmount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)) exactly to match"))
                    .font(.footnote)
                    .foregroundStyle(matches ? .green : .secondary)
                    .padding(.top, 8)
            }

            Button {
                Task {
                    if await viewModel.matchSelected(to: matchedTransaction) {
                        onMatched()
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    Text("Match")
                    if viewModel.isSubmitting {
                        Spacer()
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.matchesExactly(matchedTransaction) || viewModel.isSubmitting)
            .padding()
            .accessibilityIdentifier("confirmMatchTransactions")
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: Wellspent_V1_Transaction, viewModel: MatchTransactionsViewModel) -> some View {
        Button {
            if viewModel.selectedIDs.contains(candidate.id) {
                viewModel.selectedIDs.remove(candidate.id)
            } else {
                viewModel.selectedIDs.insert(candidate.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .foregroundStyle(.primary)
                    Text(MoneyFormatting.format(
                        units: candidate.amount.units,
                        nanos: candidate.amount.nanos,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: viewModel.selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedIDs.contains(candidate.id) ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("matchTransactionsCandidate_\(candidate.name)")
    }
}

#Preview {
    MatchTransactionsSheet(
        matchedTransaction: .with { $0.id = "fe-1"; $0.name = "Rent"; $0.plannedAmount = .with { $0.units = 500 } },
        budgetPeriodID: "preview-period",
        budgetProfileID: "preview-budget",
        currencyCode: "USD",
        localeIdentifier: "en",
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        onMatched: {}
    )
}
