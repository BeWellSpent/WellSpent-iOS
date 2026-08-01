import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionReviewMatching")
struct TransactionReviewMatchingTests {
    private func review(id: String, transactionID: String, matchedTransactionID: String, status: String, matchedName: String = "") -> Wellspent_V1_TransactionReview {
        .with {
            $0.id = id
            $0.transactionID = transactionID
            $0.matchedTransactionID = matchedTransactionID
            $0.status = status
            $0.matchedTransactionName = matchedName
        }
    }

    @Test("confirmedTransactionIDs only includes confirmed reviews")
    func confirmedTransactionIDsFiltersByStatus() {
        let reviews = [
            review(id: "1", transactionID: "tx-1", matchedTransactionID: "fx-1", status: "confirmed"),
            review(id: "2", transactionID: "tx-2", matchedTransactionID: "fx-1", status: "pending"),
            review(id: "3", transactionID: "tx-3", matchedTransactionID: "fx-2", status: "dismissed"),
        ]

        #expect(TransactionReviewMatching.confirmedTransactionIDs(reviews) == ["tx-1"])
    }

    @Test("pendingMatchName finds the matched name for a pending review, nil otherwise")
    func pendingMatchNameFindsPendingOnly() {
        let reviews = [
            review(id: "1", transactionID: "tx-1", matchedTransactionID: "fx-1", status: "pending", matchedName: "Netflix"),
            review(id: "2", transactionID: "tx-2", matchedTransactionID: "fx-2", status: "confirmed", matchedName: "Spotify"),
        ]

        #expect(TransactionReviewMatching.pendingMatchName(forTransactionID: "tx-1", reviews: reviews) == "Netflix")
        #expect(TransactionReviewMatching.pendingMatchName(forTransactionID: "tx-2", reviews: reviews) == nil)
        #expect(TransactionReviewMatching.pendingMatchName(forTransactionID: "tx-3", reviews: reviews) == nil)
    }

    @Test("linkedReviews only includes confirmed reviews matched to the given fixed transaction")
    func linkedReviewsFiltersByFixedIDAndStatus() {
        let reviews = [
            review(id: "1", transactionID: "tx-1", matchedTransactionID: "fx-1", status: "confirmed"),
            review(id: "2", transactionID: "tx-2", matchedTransactionID: "fx-1", status: "pending"),
            review(id: "3", transactionID: "tx-3", matchedTransactionID: "fx-2", status: "confirmed"),
        ]

        let linked = TransactionReviewMatching.linkedReviews(forFixedTransactionID: "fx-1", reviews: reviews)
        #expect(linked.map(\.id) == ["1"])
    }
}
