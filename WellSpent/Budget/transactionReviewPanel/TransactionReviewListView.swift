import SwiftUI
import WellSpentAPI

/// Owned by `BudgetDetailView` (not created locally here) — the pending
/// count backs the Review tab's badge, so the view model needs to be shared
/// with the outer, persistently-rendered level the same way
/// `NotificationBellViewModel` already is. See the "nested-NavigationStack
/// chrome bug" note in `CLAUDE.md` for why title/toolbar/shared state for
/// this screen lives in `BudgetDetailView`.
struct TransactionReviewListView: View {
    let viewModel: TransactionReviewViewModel?
    let currencyCode: String
    let localeIdentifier: String
    /// See `ExpensePlanView.isActive` — reloads when this tab becomes
    /// selected again, since `TabView` keeps every tab mounted.
    let isActive: Bool
    let canEdit: Bool

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Review")
        .onChange(of: isActive) { _, newValue in
            if newValue {
                Task { await viewModel?.load() }
            }
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: TransactionReviewViewModel) -> some View {
        List {
            if viewModel.reviews.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if viewModel.pendingReviews.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Nothing to review")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("transactionReviewEmptyState")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(ReviewGrouping.group(viewModel.pendingReviews)) { group in
                        reviewGroupRow(group, viewModel: viewModel)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    private func reviewGroupRow(_ group: ReviewGroup, viewModel: TransactionReviewViewModel) -> some View {
        let isSplit = group.reviews.count > 1
        let total = TransactionAmountFormatting.sum(group.reviews.map { (units: $0.transactionAmount.units, nanos: $0.transactionAmount.nanos) })

        return VStack(alignment: .leading, spacing: 8) {
            if !group.matchedTransactionName.isEmpty {
                Text("Matches \(group.matchedTransactionName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.reviews, id: \.id) { review in
                HStack {
                    Text(review.transactionName)
                        .font(.headline)
                    Spacer()
                    Text(MoneyFormatting.format(
                        units: review.transactionAmount.units,
                        nanos: review.transactionAmount.nanos,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    ))
                    .font(.headline)
                }
            }

            if isSplit {
                HStack {
                    Text("Total")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(MoneyFormatting.format(units: total.units, nanos: total.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            }

            if viewModel.spansOutsideMyView(group) {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.caption)
                    Text("Involves someone else's data — switch to Full View to review it.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("reviewSpansOutsideView_\(group.matchedTransactionID)")
            }

            HStack {
                if !isSplit {
                    Text("\(Int(group.reviews[0].matchScore))% match")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(group.reviews[0].matchScore >= 90 ? .green.opacity(0.2) : .orange.opacity(0.2))
                        .foregroundStyle(group.reviews[0].matchScore >= 90 ? .green : .orange)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("reviewScore_\(group.reviews[0].id)")
                }

                Spacer()

                if canEdit {
                    Button("Dismiss") {
                        Task { await viewModel.dismissGroup(group) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dismissReview_\(group.matchedTransactionID)")

                    Button("Confirm") {
                        Task { await viewModel.confirmGroup(group) }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("confirmReview_\(group.matchedTransactionID)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("reviewRow_\(group.matchedTransactionName)")
    }
}

#Preview {
    NavigationStack {
        TransactionReviewListView(
            viewModel: TransactionReviewViewModel(
                budgetProfileID: "preview-budget",
                authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
            ),
            currencyCode: "USD",
            localeIdentifier: "en",
            isActive: true,
            canEdit: true
        )
    }
}
