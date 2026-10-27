import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("MergedTransactionGrouping")
struct MergedTransactionGroupingTests {
    private let fixedTypeID: Int32 = 1
    private let variableTypeID: Int32 = 2

    private func transaction(
        id: String,
        typeID: Int32,
        isPaid: Bool = false,
        categoryID: Int32 = 1,
        units: Int64 = 10,
        daysFromToday: Int = 0,
        isExcluded: Bool = false
    ) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.transactionTypeID = typeID
            $0.isPaid = isPaid
            $0.categoryID = categoryID
            $0.isExcluded = isExcluded
            $0.amount = .with { $0.units = units }
            $0.date = Google_Protobuf_Timestamp(dateOnly: Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date())!)
        }
    }

    // MARK: partition

    @Test("unpaid Fixed rows float out, paid Fixed and Variable rows stay in rest")
    func partitionSplitsUnpaidFixedFromEverythingElse() {
        let unpaid = transaction(id: "unpaid-fixed", typeID: fixedTypeID, isPaid: false)
        let paid = transaction(id: "paid-fixed", typeID: fixedTypeID, isPaid: true)
        let variable = transaction(id: "variable", typeID: variableTypeID)

        let result = MergedTransactionGrouping.partition([unpaid, paid, variable], fixedTypeID: fixedTypeID)

        #expect(result.unpaidFixed.map(\.id) == ["unpaid-fixed"])
        #expect(Set(result.rest.map(\.id)) == ["paid-fixed", "variable"])
    }

    @Test("unpaidFixed sorts soonest due first")
    func unpaidFixedSortsBySoonestDue() {
        let later = transaction(id: "later", typeID: fixedTypeID, daysFromToday: 10)
        let soon = transaction(id: "soon", typeID: fixedTypeID, daysFromToday: 1)

        let result = MergedTransactionGrouping.partition([later, soon], fixedTypeID: fixedTypeID)

        #expect(result.unpaidFixed.map(\.id) == ["soon", "later"])
    }

    @Test("a Variable-typed isPaid row never counts as unpaid Fixed")
    func variableNeverFloatsEvenIfMarkedUnpaid() {
        let variable = transaction(id: "variable", typeID: variableTypeID, isPaid: false)

        let result = MergedTransactionGrouping.partition([variable], fixedTypeID: fixedTypeID)

        #expect(result.unpaidFixed.isEmpty)
        #expect(result.rest.map(\.id) == ["variable"])
    }

    // MARK: passesVariableOnlyFilter

    @Test("a Fixed row always passes the Variable-only quick filter, regardless of which one is active")
    func fixedRowAlwaysPassesQuickFilter() {
        let fixed = transaction(id: "fixed", typeID: fixedTypeID)
        for filter in VariableQuickFilter.allCases {
            #expect(MergedTransactionGrouping.passesVariableOnlyFilter(
                fixed,
                fixedTypeID: fixedTypeID,
                filter: filter,
                categoryName: { _ in "Rent" },
                hasPendingMatch: { _ in false }
            ))
        }
    }

    @Test("a Variable row is still filtered by the quick filter radio")
    func variableRowStillFiltered() {
        let received = transaction(id: "received", typeID: variableTypeID, units: -10)
        #expect(!MergedTransactionGrouping.passesVariableOnlyFilter(
            received,
            fixedTypeID: fixedTypeID,
            filter: .moneyOut,
            categoryName: { _ in "Groceries" },
            hasPendingMatch: { _ in false }
        ))
    }

    // MARK: applyFilters

    @Test("excludedOnly applies uniformly to Fixed and Variable rows")
    func excludedOnlyAppliesToBothTypes() {
        let excludedFixed = transaction(id: "excluded-fixed", typeID: fixedTypeID, isExcluded: true)
        let includedFixed = transaction(id: "included-fixed", typeID: fixedTypeID, isExcluded: false)
        let excludedVariable = transaction(id: "excluded-variable", typeID: variableTypeID, isExcluded: true)

        let result = MergedTransactionGrouping.applyFilters(
            [excludedFixed, includedFixed, excludedVariable],
            fixedTypeID: fixedTypeID,
            filter: .all,
            exceededOnly: false,
            excludedOnly: true,
            searchQuery: "",
            incomeCategoryID: nil,
            overBudgetTransactionIDs: [],
            categoryName: { _ in nil },
            ownerName: { _ in nil },
            hasPendingMatch: { _ in false }
        )

        #expect(Set(result.map(\.id)) == ["excluded-fixed", "excluded-variable"])
    }

    @Test("search applies to both types")
    func searchAppliesToBothTypes() {
        let fixedMatch = Wellspent_V1_Transaction.with {
            $0.id = "fixed-rent"
            $0.name = "Rent"
            $0.transactionTypeID = fixedTypeID
        }
        let variableNoMatch = Wellspent_V1_Transaction.with {
            $0.id = "variable-coffee"
            $0.name = "Coffee"
            $0.transactionTypeID = variableTypeID
        }

        let result = MergedTransactionGrouping.applyFilters(
            [fixedMatch, variableNoMatch],
            fixedTypeID: fixedTypeID,
            filter: .all,
            exceededOnly: false,
            excludedOnly: false,
            searchQuery: "rent",
            incomeCategoryID: nil,
            overBudgetTransactionIDs: [],
            categoryName: { _ in nil },
            ownerName: { _ in nil },
            hasPendingMatch: { _ in false }
        )

        #expect(result.map(\.id) == ["fixed-rent"])
    }
}
