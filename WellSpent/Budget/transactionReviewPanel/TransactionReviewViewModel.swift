import Observation
import WellSpentAPI

@MainActor
@Observable
final class TransactionReviewViewModel {
    private(set) var isLoading = false
    private(set) var reviews: [Wellspent_V1_TransactionReview] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currentUserID: String?

    private let client: Wellspent_V1_BudgetServiceClient

    /// `ListTransactionReviews` doesn't filter by status server-side —
    /// mirrors web's `TransactionReviewPanel.tsx`, which client-filters to
    /// `pending` itself and exports a `transactionReviewCount` helper for
    /// its tab badge (this computed property is the Swift equivalent).
    var pendingReviews: [Wellspent_V1_TransactionReview] {
        reviews.filter { $0.status == "pending" }
    }

    /// The review queue is never filtered by Focused View — an actionable
    /// item shouldn't be hidden behind a display toggle — but a row that
    /// involves someone other than the caller gets flagged instead, using
    /// the resolved person ids the backend attaches to each side of a match.
    func spansOutsideMyView(_ review: Wellspent_V1_TransactionReview) -> Bool {
        guard let myPerson = ChartPreference.myPerson(currentUserID: currentUserID, people: people),
              myPerson.focusedViewEnabled else { return false }
        func involvesSomeoneElse(_ personID: Int64) -> Bool {
            personID != 0 && personID != myPerson.id
        }
        return involvesSomeoneElse(review.transactionPersonID) || involvesSomeoneElse(review.matchedTransactionPersonID)
    }

    init(budgetProfileID: String, currentUserID: String? = nil, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    /// Not private, so `pendingReviews`/`spansOutsideMyView` are testable
    /// without a live `ListTransactionReviews`/`ListBudgetPeople` call.
    func setStateForTesting(reviews: [Wellspent_V1_TransactionReview], people: [Wellspent_V1_BudgetPerson] = []) {
        self.reviews = reviews
        self.people = people
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

        async let reviewsResponse = client.listTransactionReviews(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await reviewsResponse.result {
        case .success(let message):
            reviews = message.reviews
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load transaction reviews."
        }
        if case .success(let message) = await peopleResponse.result {
            people = message.people
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
            // `ConfirmTransactionReviewResponse` carries no body, so the
            // updated review is synthesized locally rather than removed.
            // `TransactionReviewMatching.confirmedTransactionIDs`/
            // `linkedReviews` (consumed by the Transactions tab, sharing
            // this same view model instance) key off a *present* review
            // with `status == "confirmed"` — removing the row outright (as
            // this used to do) meant the Variable row only disappeared and
            // the Fixed sub-row only appeared once the next `pollPendingCount()`
            // tick refetched from the server, up to 30s later, instead of
            // immediately.
            if let index = reviews.firstIndex(where: { $0.id == review.id }) {
                reviews[index].status = "confirmed"
            }
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
