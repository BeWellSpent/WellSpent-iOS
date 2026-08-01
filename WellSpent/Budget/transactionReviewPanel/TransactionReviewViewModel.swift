import Observation
import WellSpentAPI

@MainActor
@Observable
final class TransactionReviewViewModel {
    private(set) var isLoading = false
    private(set) var reviews: [Wellspent_V1_TransactionReview] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient

    /// `ListTransactionReviews` doesn't filter by status server-side —
    /// mirrors web's `TransactionReviewPanel.tsx`, which client-filters to
    /// `pending` itself and exports a `transactionReviewCount` helper for
    /// its tab badge (this computed property is the Swift equivalent).
    var pendingReviews: [Wellspent_V1_TransactionReview] {
        reviews.filter { $0.status == "pending" }
    }

    init(budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    /// Not private, so `pendingReviews` is testable without a live
    /// `ListTransactionReviews` call.
    func setStateForTesting(reviews: [Wellspent_V1_TransactionReview]) {
        self.reviews = reviews
    }

    /// Started once from `BudgetDetailView`'s own `.task` (same shape as
    /// `NotificationBellViewModel.pollUnreadCount()`) so the Review tab's
    /// badge — visible from every tab — reflects new matches without the
    /// user having to enter the tab first. Web gets this for free from React
    /// Query's cache invalidation across mutations; there's no equivalent
    /// shared-cache mechanism here, so polling is the direct substitute.
    func pollPendingCount() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response = await client.listTransactionReviews(request: .with { $0.budgetProfileID = budgetProfileID })
        switch response.result {
        case .success(let message):
            reviews = message.reviews
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load transaction reviews."
        }
    }

    /// Confirming links the import to the matched fixed-type transaction and
    /// excludes the imported variable transaction from totals (it is not
    /// deleted — `transaction_service.go`'s `ConfirmTransactionReview` calls
    /// `SetExcluded`, not a delete, so it stays visible/toggleable in the
    /// Transactions tab rather than disappearing behind this review's own
    /// side channel; `docs/features/transaction-review.md`'s "deletes the
    /// variable transaction" line is stale).
    func confirm(_ review: Wellspent_V1_TransactionReview) async {
        errorMessage = nil
        let response = await client.confirmTransactionReview(request: .with {
            $0.reviewID = review.id
            $0.budgetProfileID = budgetProfileID
        })
        switch response.result {
        case .success:
            reviews.removeAll { $0.id == review.id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't confirm that match."
        }
    }

    func dismiss(_ review: Wellspent_V1_TransactionReview) async {
        errorMessage = nil
        let response = await client.dismissTransactionReview(request: .with { $0.reviewID = review.id })
        switch response.result {
        case .success:
            reviews.removeAll { $0.id == review.id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't dismiss that match."
        }
    }
}
