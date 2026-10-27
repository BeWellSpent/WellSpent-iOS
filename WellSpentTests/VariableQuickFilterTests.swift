import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("VariableQuickFiltering")
struct VariableQuickFilterTests {
    private func transaction(id: String, units: Int64 = 10, categoryID: Int32 = 1) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.name = "Groceries"
            $0.amount = .with { $0.units = units }
            $0.categoryID = categoryID
        }
    }

    // MARK: matches

    @Test("moneyOut keeps only non-received (spent) amounts")
    func moneyOutKeepsSpent() {
        let spent = transaction(id: "1", units: 20)
        let received = transaction(id: "2", units: -20)

        #expect(VariableQuickFiltering.matches(spent, filter: .moneyOut, categoryName: { _ in "Groceries" }, hasPendingMatch: { _ in false }))
        #expect(!VariableQuickFiltering.matches(received, filter: .moneyOut, categoryName: { _ in "Groceries" }, hasPendingMatch: { _ in false }))
    }

    @Test("moneyIn keeps only received amounts")
    func moneyInKeepsReceived() {
        let spent = transaction(id: "1", units: 20)
        let received = transaction(id: "2", units: -20)

        #expect(!VariableQuickFiltering.matches(spent, filter: .moneyIn, categoryName: { _ in "Groceries" }, hasPendingMatch: { _ in false }))
        #expect(VariableQuickFiltering.matches(received, filter: .moneyIn, categoryName: { _ in "Groceries" }, hasPendingMatch: { _ in false }))
    }

    @Test("needsReview matches an uncategorized transaction")
    func needsReviewMatchesUncategorized() {
        let uncategorized = transaction(id: "1", categoryID: 0)
        #expect(VariableQuickFiltering.matches(uncategorized, filter: .needsReview, categoryName: { _ in nil }, hasPendingMatch: { _ in false }))
    }

    @Test("needsReview matches a transaction with a pending fixed-expense match")
    func needsReviewMatchesPendingMatch() {
        let pending = transaction(id: "1")
        #expect(VariableQuickFiltering.matches(pending, filter: .needsReview, categoryName: { _ in "Groceries" }, hasPendingMatch: { _ in true }))
    }

    @Test("needsReview does not match a categorized transaction with no pending match")
    func needsReviewExcludesResolvedTransaction() {
        let resolved = transaction(id: "1")
        #expect(!VariableQuickFiltering.matches(resolved, filter: .needsReview, categoryName: { _ in "Groceries" }, hasPendingMatch: { _ in false }))
    }

    @Test("all matches everything")
    func allMatchesEverything() {
        let transaction = transaction(id: "1", units: -20, categoryID: 0)
        #expect(VariableQuickFiltering.matches(transaction, filter: .all, categoryName: { _ in nil }, hasPendingMatch: { _ in false }))
    }

    // MARK: apply

    @Test("apply combines quick filter, exceeded/excluded toggles, and search")
    func applyCombinesEveryPredicate() {
        let match = transaction(id: "1", units: 20)
        let excludedByQuickFilter = transaction(id: "2", units: -20)
        let excludedBySearch = transaction(id: "3", units: 20)

        let result = VariableQuickFiltering.apply(
            [match, excludedByQuickFilter, excludedBySearch],
            filter: .moneyOut,
            exceededOnly: false,
            excludedOnly: false,
            searchQuery: "groceries",
            incomeCategoryID: nil,
            overBudgetTransactionIDs: [],
            categoryName: { _ in "Groceries" },
            ownerName: { _ in nil },
            hasPendingMatch: { _ in false }
        )

        #expect(result.map(\.id) == ["1", "3"])
    }

    @Test("apply's exceededOnly toggle keeps only flagged transaction ids")
    func applyExceededOnlyKeepsFlaggedIDs() {
        let flagged = transaction(id: "1")
        let notFlagged = transaction(id: "2")

        let result = VariableQuickFiltering.apply(
            [flagged, notFlagged],
            filter: .all,
            exceededOnly: true,
            excludedOnly: false,
            searchQuery: "",
            incomeCategoryID: nil,
            overBudgetTransactionIDs: ["1"],
            categoryName: { _ in "Groceries" },
            ownerName: { _ in nil },
            hasPendingMatch: { _ in false }
        )

        #expect(result.map(\.id) == ["1"])
    }

    // MARK: needsReviewCount

    @Test("needsReviewCount counts against the full list, independent of the active quick filter")
    func needsReviewCountCountsAll() {
        let uncategorized = transaction(id: "1", categoryID: 0)
        let categorized = transaction(id: "2", categoryID: 1)
        let count = VariableQuickFiltering.needsReviewCount(
            [uncategorized, categorized],
            categoryName: { id in id == 0 ? nil : "Groceries" },
            hasPendingMatch: { _ in false }
        )
        #expect(count == 1)
    }
}
