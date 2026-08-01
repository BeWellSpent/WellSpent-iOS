import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionReviewViewModel")
@MainActor
struct TransactionReviewViewModelTests {
    private func makeViewModel() -> TransactionReviewViewModel {
        TransactionReviewViewModel(budgetProfileID: "profile-1", authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    private func review(id: String, status: String) -> Wellspent_V1_TransactionReview {
        .with { $0.id = id; $0.status = status; $0.transactionName = "Review \(id)" }
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
}
