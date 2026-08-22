import SwiftUI
import WellSpentAPI

struct MarkForReviewSheet: View {
    let transaction: Wellspent_V1_Transaction
    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let authenticatedClient: ProtocolClient
    let onMarked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MarkForReviewViewModel?
    @State private var selectedID: String?
    @State private var filter = ""
    /// Unpaid candidates are far more likely to be the intended match, so
    /// they stay uncollapsed; paid ones are tucked behind this toggle — same
    /// split as the Fixed tab itself (docs/features/transactions.md).
    @State private var isPaidExpanded = false

    private var filteredCandidates: [Wellspent_V1_Transaction] {
        guard let viewModel else { return [] }
        guard !filter.isEmpty else { return viewModel.fixedTransactions }
        return viewModel.fixedTransactions.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var unpaidCandidates: [Wellspent_V1_Transaction] {
        filteredCandidates.filter { !$0.isPaid }
    }

    private var paidCandidates: [Wellspent_V1_Transaction] {
        filteredCandidates.filter(\.isPaid)
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
            .sheetChrome(Text("Flag for Review")) { dismiss() }
            .task {
                if viewModel == nil {
                    viewModel = MarkForReviewViewModel(
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
    private func content(viewModel: MarkForReviewViewModel) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.name)
                    .font(.headline)
                Text(MoneyFormatting.format(
                    units: transaction.amount.units,
                    nanos: transaction.amount.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            List {
                if viewModel.isLoading {
                    ProgressView()
                } else if filteredCandidates.isEmpty {
                    (filter.isEmpty ? Text("No fixed expenses yet.") : Text("No matches."))
                        .foregroundStyle(.secondary)
                } else {
                    if !unpaidCandidates.isEmpty {
                        if !paidCandidates.isEmpty {
                            Text("Unpaid (\(unpaidCandidates.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(unpaidCandidates, id: \.id) { candidate in
                            candidateRow(candidate)
                        }
                    }

                    if !paidCandidates.isEmpty {
                        Button {
                            isPaidExpanded.toggle()
                        } label: {
                            HStack {
                                Text("Paid (\(paidCandidates.count))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: isPaidExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("togglePaidMarkForReviewCandidates")

                        if isPaidExpanded {
                            ForEach(paidCandidates, id: \.id) { candidate in
                                candidateRow(candidate)
                            }
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .searchable(text: $filter)

            Button {
                guard let selectedID, let candidate = viewModel.fixedTransactions.first(where: { $0.id == selectedID }) else { return }
                Task {
                    if await viewModel.markForReview(transaction: transaction, matchedTransaction: candidate) {
                        onMarked()
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    Text("Confirm Match")
                    if viewModel.isSubmitting {
                        Spacer()
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedID == nil || viewModel.isSubmitting)
            .padding()
            .accessibilityIdentifier("confirmMarkForReview")
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: Wellspent_V1_Transaction) -> some View {
        Button {
            selectedID = candidate.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .foregroundStyle(.primary)
                    Text(MoneyFormatting.format(
                        units: candidate.plannedAmount.units,
                        nanos: candidate.plannedAmount.nanos,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedID == candidate.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("markForReviewCandidate_\(candidate.name)")
    }
}

#Preview {
    MarkForReviewSheet(
        transaction: .with { $0.id = "tx-1"; $0.name = "NETFLIX.COM"; $0.amount = .with { $0.units = 15 } },
        budgetPeriodID: "preview-period",
        budgetProfileID: "preview-budget",
        currencyCode: "USD",
        localeIdentifier: "en",
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        onMarked: {}
    )
}
