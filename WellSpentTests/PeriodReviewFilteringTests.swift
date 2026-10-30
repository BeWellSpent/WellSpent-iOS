import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PeriodReviewFiltering")
struct PeriodReviewFilteringTests {
    private func transaction(id: String, carriedFrom: String = "", typeID: Int32 = 2, isPaid: Bool = false) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.carriedFromBudgetPeriodID = carriedFrom
            $0.transactionTypeID = typeID
            $0.isPaid = isPaid
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

    @Test("unpaidFixedTransactions keeps only Fixed-type, unpaid rows")
    func unpaidFixedFiltersCorrectly() {
        let transactions = [
            transaction(id: "fixed-unpaid", typeID: 1, isPaid: false),
            transaction(id: "fixed-paid", typeID: 1, isPaid: true),
            transaction(id: "variable-unpaid", typeID: 2, isPaid: false),
        ]
        #expect(PeriodReviewFiltering.unpaidFixedTransactions(transactions, fixedTypeID: 1).map(\.id) == ["fixed-unpaid"])
    }

    @Test("unpaidFixedTransactions returns empty for no matches")
    func unpaidFixedEmptyWhenNoMatches() {
        let transactions = [transaction(id: "fixed-paid", typeID: 1, isPaid: true)]
        #expect(PeriodReviewFiltering.unpaidFixedTransactions(transactions, fixedTypeID: 1).isEmpty)
    }
}
