import Observation
import os
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class TransactionReviewViewModel {
    private static let logger = AppLogger.logger("TransactionReview")

    private(set) var isLoading = false
    private(set) var reviews: [Wellspent_V1_TransactionReview] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currentUserID: String?

    private let restClient: WellSpentREST.Client

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

    func spansOutsideMyView(_ group: ReviewGroup) -> Bool {
        group.reviews.contains { spansOutsideMyView($0) }
    }

    init(budgetProfileID: String, currentUserID: String? = nil, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.restClient = restClient
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

        async let reviewsResult = fetchReviews()
        async let peopleResult = fetchPeople()

        if let fetched = await reviewsResult {
            reviews = fetched
        }
        if let fetched = await peopleResult {
            people = fetched
        }
    }

    private func fetchReviews() async -> [Wellspent_V1_TransactionReview]? {
        do {
            let output = try await restClient.listTransactionReviews(.init(path: .init(id: budgetProfileID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load transaction reviews."
                Self.logger.error("list transaction reviews failed budgetProfileID=\(self.budgetProfileID, privacy: .public) output=\(String(describing: output), privacy: .public)")
                return nil
            }
            return body.reviews.map(BudgetRESTMapping.transactionReview(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load transaction reviews."
            Self.logger.error("list transaction reviews failed budgetProfileID=\(self.budgetProfileID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        do {
            let output = try await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                Self.logger.error("list budget people failed budgetProfileID=\(self.budgetProfileID, privacy: .public) output=\(String(describing: output), privacy: .public)")
                return nil
            }
            return body.people.map(BudgetRESTMapping.person(from:))
        } catch {
            Self.logger.error("list budget people failed budgetProfileID=\(self.budgetProfileID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
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
        let fallback = "Couldn't confirm that match."
        do {
            guard case .ok = try await restClient.confirmTransactionReview(.init(path: .init(id: review.id))) else {
                errorMessage = fallback
                Self.logger.error("confirm transaction review failed reviewID=\(review.id, privacy: .public)")
                return
            }
            // Synthesize the status locally rather than removing the row, so
            // `TransactionReviewMatching` (consumed by the Transactions tab,
            // sharing this same view model instance) sees the confirmed state
            // immediately instead of waiting for the next `pollPendingCount()`
            // tick, up to 30s later.
            if let index = reviews.firstIndex(where: { $0.id == review.id }) {
                reviews[index].status = "confirmed"
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            Self.logger.error("confirm transaction review failed reviewID=\(review.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    func dismiss(_ review: Wellspent_V1_TransactionReview) async {
        errorMessage = nil
        let fallback = "Couldn't dismiss that match."
        do {
            guard case .ok = try await restClient.dismissTransactionReview(.init(path: .init(id: review.id))) else {
                errorMessage = fallback
                Self.logger.error("dismiss transaction review failed reviewID=\(review.id, privacy: .public)")
                return
            }
            reviews.removeAll { $0.id == review.id }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            Self.logger.error("dismiss transaction review failed reviewID=\(review.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    // Sequential, not a task group — each confirm must see the last one's write.
    func confirmGroup(_ group: ReviewGroup) async {
        for review in group.reviews {
            await confirm(review)
        }
    }

    func dismissGroup(_ group: ReviewGroup) async {
        for review in group.reviews {
            await dismiss(review)
        }
    }
}
