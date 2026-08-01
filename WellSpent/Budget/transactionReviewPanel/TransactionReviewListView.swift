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
                    ForEach(viewModel.pendingReviews, id: \.id) { review in
                        reviewRow(review, viewModel: viewModel)
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

    private func reviewRow(_ review: Wellspent_V1_TransactionReview, viewModel: TransactionReviewViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.transactionName)
                        .font(.headline)
                    if !review.matchedTransactionName.isEmpty {
                        Text("Matches \(review.matchedTransactionName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(MoneyFormatting.format(
                    units: review.transactionAmount.units,
                    nanos: review.transactionAmount.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))
                .font(.headline)
            }

            HStack {
                Text("\(Int(review.matchScore))% match")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(review.matchScore >= 90 ? .green.opacity(0.2) : .orange.opacity(0.2))
                    .foregroundStyle(review.matchScore >= 90 ? .green : .orange)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("reviewScore_\(review.id)")

                Spacer()

                if canEdit {
                    Button("Dismiss") {
                        Task { await viewModel.dismiss(review) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dismissReview_\(review.id)")

                    Button("Confirm") {
                        Task { await viewModel.confirm(review) }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("confirmReview_\(review.id)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("reviewRow_\(review.transactionName)")
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
