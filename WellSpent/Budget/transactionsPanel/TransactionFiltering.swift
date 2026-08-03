import Foundation
import WellSpentAPI

/// Mirrors web's `FilterOption`/filter predicates and `matchesSearch`
/// (`transactionsPanel/helpers.ts`). `exceededOnly` is only ever applied to
/// Variable transactions (no Fixed-tab equivalent, matching web).
nonisolated enum TransactionFilterOption: String, CaseIterable {
    case none
    case spentOnly
    case exceededOnly
    case excludedOnly

    var label: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .none: return String(localized: "All transactions", locale: locale)
        case .spentOnly: return String(localized: "Spent only", locale: locale)
        case .exceededOnly: return String(localized: "Exceeded only", locale: locale)
        case .excludedOnly: return String(localized: "Excluded only", locale: locale)
        }
    }
}

nonisolated enum TransactionFiltering {
    static func matchesSearch(name: String, categoryName: String?, ownerName: String?, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        if name.lowercased().contains(q) { return true }
        if let categoryName, categoryName.lowercased().contains(q) { return true }
        if let ownerName, ownerName.lowercased().contains(q) { return true }
        return false
    }

    static func apply(
        _ transactions: [Wellspent_V1_Transaction],
        filter: TransactionFilterOption,
        searchQuery: String,
        incomeCategoryID: Int32?,
        overBudgetTransactionIDs: Set<String>,
        categoryName: (Int32) -> String?,
        ownerName: (String) -> String?
    ) -> [Wellspent_V1_Transaction] {
        transactions.filter { transaction in
            switch filter {
            case .none:
                break
            case .spentOnly:
                guard !TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos) else { return false }
            case .exceededOnly:
                guard overBudgetTransactionIDs.contains(transaction.id) else { return false }
            case .excludedOnly:
                guard ExpenseOverviewCalculations.isTransactionExcluded(transaction, incomeCategoryID: incomeCategoryID) else { return false }
            }
            return matchesSearch(
                name: transaction.name,
                categoryName: categoryName(transaction.categoryID),
                ownerName: ownerName(transaction.paymentMethodID),
                query: searchQuery
            )
        }
    }

    /// Mirrors web's `computeOverBudgetTxIds`: for each category, walks its
    /// Variable transactions in chronological (date-ascending) order,
    /// summing spent amounts, and flags every transaction from the point the
    /// running sum first exceeds that category's planned total onward.
    static func overBudgetTransactionIDs(
        variableTransactions: [Wellspent_V1_Transaction],
        plannedTotal: (Int32) -> (units: Int64, nanos: Int32)
    ) -> Set<String> {
        var flagged: Set<String> = []
        let byCategory = Dictionary(grouping: variableTransactions, by: \.categoryID)

        for (categoryID, transactions) in byCategory {
            let planned = plannedTotal(categoryID)
            guard planned.units != 0 || planned.nanos != 0 else { continue }

            let chronological = transactions.sorted { $0.date.date < $1.date.date }
            var runningTotal: (units: Int64, nanos: Int32) = (0, 0)
            var hasExceeded = false

            for transaction in chronological {
                guard !TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos) else { continue }
                runningTotal = TransactionAmountFormatting.sum([
                    (units: runningTotal.units, nanos: runningTotal.nanos),
                    (units: transaction.amount.units, nanos: transaction.amount.nanos)
                ])
                if !hasExceeded {
                    hasExceeded = runningTotal.units > planned.units
                        || (runningTotal.units == planned.units && runningTotal.nanos > planned.nanos)
                }
                if hasExceeded {
                    flagged.insert(transaction.id)
                }
            }
        }

        return flagged
    }
}
