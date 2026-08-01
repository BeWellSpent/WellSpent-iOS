import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionFiltering")
struct TransactionFilteringTests {
    private func transaction(
        id: String,
        name: String = "Groceries",
        units: Int64 = 10,
        categoryID: Int32 = 1,
        isExcluded: Bool = false,
        daysAgo: Int = 0
    ) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.name = name
            $0.amount = .with { $0.units = units }
            $0.categoryID = categoryID
            $0.isExcluded = isExcluded
            $0.date = Google_Protobuf_Timestamp(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!)
        }
    }

    // MARK: matchesSearch

    @Test("matchesSearch matches name, category, or owner case-insensitively")
    func matchesSearchMatchesAnyField() {
        #expect(TransactionFiltering.matchesSearch(name: "Groceries", categoryName: "Food", ownerName: "Alex", query: "groc"))
        #expect(TransactionFiltering.matchesSearch(name: "Groceries", categoryName: "Food", ownerName: "Alex", query: "FOOD"))
        #expect(TransactionFiltering.matchesSearch(name: "Groceries", categoryName: "Food", ownerName: "Alex", query: "alex"))
        #expect(!TransactionFiltering.matchesSearch(name: "Groceries", categoryName: "Food", ownerName: "Alex", query: "rent"))
    }

    @Test("matchesSearch with an empty query matches everything")
    func matchesSearchEmptyQueryMatchesAll() {
        #expect(TransactionFiltering.matchesSearch(name: "Groceries", categoryName: nil, ownerName: nil, query: ""))
    }

    // MARK: apply — filter predicates

    @Test("spentOnly keeps only positive (spent) amounts")
    func spentOnlyKeepsPositiveAmounts() {
        let spent = transaction(id: "1", units: 20)
        let received = transaction(id: "2", units: -20)

        let result = TransactionFiltering.apply(
            [spent, received], filter: .spentOnly, searchQuery: "",
            incomeCategoryID: nil, overBudgetTransactionIDs: [],
            categoryName: { _ in nil }, ownerName: { _ in nil }
        )

        #expect(result.map(\.id) == ["1"])
    }

    @Test("excludedOnly keeps only manually-excluded or Income-category transactions")
    func excludedOnlyKeepsExcludedOrIncome() {
        let excluded = transaction(id: "1", isExcluded: true)
        let income = transaction(id: "2", categoryID: 99)
        let normal = transaction(id: "3")

        let result = TransactionFiltering.apply(
            [excluded, income, normal], filter: .excludedOnly, searchQuery: "",
            incomeCategoryID: 99, overBudgetTransactionIDs: [],
            categoryName: { _ in nil }, ownerName: { _ in nil }
        )

        #expect(Set(result.map(\.id)) == ["1", "2"])
    }

    @Test("exceededOnly keeps only flagged transaction ids")
    func exceededOnlyKeepsFlaggedIDs() {
        let flagged = transaction(id: "1")
        let notFlagged = transaction(id: "2")

        let result = TransactionFiltering.apply(
            [flagged, notFlagged], filter: .exceededOnly, searchQuery: "",
            incomeCategoryID: nil, overBudgetTransactionIDs: ["1"],
            categoryName: { _ in nil }, ownerName: { _ in nil }
        )

        #expect(result.map(\.id) == ["1"])
    }

    @Test("none filter combined with a search query still filters by search")
    func noneFilterStillAppliesSearch() {
        let match = transaction(id: "1", name: "Rent")
        let noMatch = transaction(id: "2", name: "Groceries")

        let result = TransactionFiltering.apply(
            [match, noMatch], filter: .none, searchQuery: "rent",
            incomeCategoryID: nil, overBudgetTransactionIDs: [],
            categoryName: { _ in nil }, ownerName: { _ in nil }
        )

        #expect(result.map(\.id) == ["1"])
    }

    // MARK: overBudgetTransactionIDs

    @Test("a category under its planned total flags nothing")
    func categoryUnderBudgetFlagsNothing() {
        let transactions = [
            transaction(id: "1", units: 10, categoryID: 1, daysAgo: 2),
            transaction(id: "2", units: 10, categoryID: 1, daysAgo: 1)
        ]

        let ids = TransactionFiltering.overBudgetTransactionIDs(variableTransactions: transactions) { _ in (units: 100, nanos: 0) }

        #expect(ids.isEmpty)
    }

    @Test("only transactions from the point the running total crosses the plan are flagged")
    func onlyTransactionsFromCrossingPointAreFlagged() {
        // Chronological: t1 (day 2 ago, 10), t2 (day 1 ago, 10), t3 (today, 10) — planned 15.
        // Running total: 10, 20 (crosses here), 30 -> t2 and t3 flagged, t1 is not.
        let t1 = transaction(id: "t1", units: 10, categoryID: 1, daysAgo: 2)
        let t2 = transaction(id: "t2", units: 10, categoryID: 1, daysAgo: 1)
        let t3 = transaction(id: "t3", units: 10, categoryID: 1, daysAgo: 0)

        let ids = TransactionFiltering.overBudgetTransactionIDs(variableTransactions: [t1, t2, t3]) { _ in (units: 15, nanos: 0) }

        #expect(ids == ["t2", "t3"])
    }

    @Test("categories with a zero planned total are skipped entirely")
    func zeroPlannedTotalCategoryIsSkipped() {
        let transactions = [transaction(id: "1", units: 1000, categoryID: 1)]

        let ids = TransactionFiltering.overBudgetTransactionIDs(variableTransactions: transactions) { _ in (units: 0, nanos: 0) }

        #expect(ids.isEmpty)
    }
}
