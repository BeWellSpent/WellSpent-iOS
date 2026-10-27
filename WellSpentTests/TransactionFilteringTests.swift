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

    // MARK: apply — search only, now that the legacy filter menu is gone

    @Test("apply with an empty query returns every transaction")
    func applyEmptyQueryReturnsAll() {
        let a = transaction(id: "1", name: "Rent")
        let b = transaction(id: "2", name: "Groceries")

        let result = TransactionFiltering.apply(
            [a, b], searchQuery: "",
            categoryName: { _ in nil }, ownerName: { _ in nil }
        )

        #expect(Set(result.map(\.id)) == ["1", "2"])
    }

    @Test("apply filters by search query against name")
    func applyFiltersBySearchQuery() {
        let match = transaction(id: "1", name: "Rent")
        let noMatch = transaction(id: "2", name: "Groceries")

        let result = TransactionFiltering.apply(
            [match, noMatch], searchQuery: "rent",
            categoryName: { _ in nil }, ownerName: { _ in nil }
        )

        #expect(result.map(\.id) == ["1"])
    }

    @Test("apply falls back to matching category or owner name")
    func applyFiltersByCategoryOrOwner() {
        let byCategory = transaction(id: "1", name: "Monthly bill", categoryID: 5)
        var byOwner = transaction(id: "2", name: "Something else")
        byOwner.paymentMethodID = "pm-alex"
        let noMatch = transaction(id: "3", name: "Unrelated")

        let result = TransactionFiltering.apply(
            [byCategory, byOwner, noMatch], searchQuery: "alex",
            categoryName: { $0 == 5 ? "Alexandria" : nil },
            ownerName: { $0 == "pm-alex" ? "Alex" : nil }
        )

        #expect(Set(result.map(\.id)) == ["1", "2"])
    }
}
