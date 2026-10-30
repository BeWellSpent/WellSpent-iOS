import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PeriodReviewFiltering")
struct PeriodReviewFilteringTests {
    private func transaction(id: String, carriedFrom: String = "") -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.carriedFromBudgetPeriodID = carriedFrom
        }
    }

    @Test("carriedOverTransactions keeps only rows carried from the given previous period")
    func carriedOverFiltersByPreviousPeriod() {
        let transactions = [
            transaction(id: "1", carriedFrom: "prev"),
            transaction(id: "2", carriedFrom: "other-period"),
            transaction(id: "3", carriedFrom: ""),
        ]
        #expect(PeriodReviewFiltering.carriedOverTransactions(transactions, previousPeriodID: "prev").map(\.id) == ["1"])
    }

    @Test("carriedOverTransactions returns empty for no matches")
    func carriedOverEmptyWhenNoMatches() {
        let transactions = [transaction(id: "1", carriedFrom: "other")]
        #expect(PeriodReviewFiltering.carriedOverTransactions(transactions, previousPeriodID: "prev").isEmpty)
    }
}
