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
        case .none: return String(localized: "All transactions", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .spentOnly: return String(localized: "Spent only", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .exceededOnly: return String(localized: "Exceeded only", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .excludedOnly: return String(localized: "Excluded only", bundle: AppLanguageStore.currentBundle, locale: locale)
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
}
