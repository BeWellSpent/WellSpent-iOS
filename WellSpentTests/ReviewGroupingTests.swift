import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ReviewGrouping")
struct ReviewGroupingTests {
    private func review(id: String, matchedID: String, matchedName: String = "Rent") -> Wellspent_V1_TransactionReview {
        .with { $0.id = id; $0.matchedTransactionID = matchedID; $0.matchedTransactionName = matchedName }
    }

    @Test("one group per distinct matched transaction")
    func oneGroupPerMatch() {
        let groups = ReviewGrouping.group([review(id: "r1", matchedID: "fe-1"), review(id: "r2", matchedID: "fe-2")])
        #expect(groups.count == 2)
    }

    @Test("groups several reviews matched to the same fixed transaction together")
    func groupsSplitMatch() {
        let groups = ReviewGrouping.group([
            review(id: "r1", matchedID: "fe-1"),
            review(id: "r2", matchedID: "fe-1"),
            review(id: "r3", matchedID: "fe-1"),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].reviews.map(\.id) == ["r1", "r2", "r3"])
    }

    @Test("preserves first-seen order of matched transactions")
    func preservesOrder() {
        let groups = ReviewGrouping.group([
            review(id: "r1", matchedID: "fe-2"),
            review(id: "r2", matchedID: "fe-1"),
            review(id: "r3", matchedID: "fe-2"),
        ])
        #expect(groups.map(\.matchedTransactionID) == ["fe-2", "fe-1"])
    }

    @Test("empty input produces no groups")
    func emptyInput() {
        #expect(ReviewGrouping.group([]).isEmpty)
    }
}
