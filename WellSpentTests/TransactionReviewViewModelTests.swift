import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionReviewViewModel")
@MainActor
struct TransactionReviewViewModelTests {
    private func makeViewModel(currentUserID: String? = nil) -> TransactionReviewViewModel {
        TransactionReviewViewModel(budgetProfileID: "profile-1", currentUserID: currentUserID, authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    private func review(id: String, status: String, transactionPersonID: Int64 = 0, matchedTransactionPersonID: Int64 = 0) -> Wellspent_V1_TransactionReview {
        .with {
            $0.id = id
            $0.status = status
            $0.transactionName = "Review \(id)"
            $0.transactionPersonID = transactionPersonID
            $0.matchedTransactionPersonID = matchedTransactionPersonID
        }
    }

    private func person(id: Int64, userID: String, focusedView: Bool) -> Wellspent_V1_BudgetPerson {
        .with { $0.id = id; $0.userID = userID; $0.focusedViewEnabled = focusedView }
    }

    @Test("pendingReviews only includes reviews with pending status")
    func pendingReviewsFiltersByStatus() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(reviews: [
            review(id: "1", status: "pending"),
            review(id: "2", status: "confirmed"),
            review(id: "3", status: "dismissed"),
            review(id: "4", status: "pending"),
        ])

        #expect(viewModel.pendingReviews.map(\.id) == ["1", "4"])
    }

    @Test("pendingReviews is empty when there are no reviews")
    func pendingReviewsEmptyWhenNoReviews() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(reviews: [])
        #expect(viewModel.pendingReviews.isEmpty)
    }

    @Test("never flags a review when Focused View is off")
    func neverFlagsWhenFocusedViewOff() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            reviews: [review(id: "1", status: "pending", transactionPersonID: 2)],
            people: [person(id: 1, userID: "me", focusedView: false)]
        )
        #expect(!viewModel.spansOutsideMyView(viewModel.reviews[0]))
    }

    @Test("flags a review whose variable-transaction side belongs to someone else")
    func flagsWhenTransactionSideIsSomeoneElse() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            reviews: [review(id: "1", status: "pending", transactionPersonID: 2)],
            people: [person(id: 1, userID: "me", focusedView: true)]
        )
        #expect(viewModel.spansOutsideMyView(viewModel.reviews[0]))
    }

    @Test("flags a review whose matched fixed-expense side belongs to someone else")
    func flagsWhenMatchedSideIsSomeoneElse() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            reviews: [review(id: "1", status: "pending", matchedTransactionPersonID: 2)],
            people: [person(id: 1, userID: "me", focusedView: true)]
        )
        #expect(viewModel.spansOutsideMyView(viewModel.reviews[0]))
    }

    @Test("does not flag a review that is fully mine plus unattributed")
    func doesNotFlagOwnReview() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            reviews: [review(id: "1", status: "pending", transactionPersonID: 1, matchedTransactionPersonID: 0)],
            people: [person(id: 1, userID: "me", focusedView: true)]
        )
        #expect(!viewModel.spansOutsideMyView(viewModel.reviews[0]))
    }
}
