import Foundation
import WellSpentAPI

/// `.exceededOnly`/`.excludedOnly` are the two real, server-backed filters
/// surfaced as independent toggle chips on the Variable tab (see
/// `TransactionsListView.quickFilterToggleChip`) — kept here purely so their
/// catalog labels aren't duplicated. The Fixed/Payments tabs' own legacy
/// toolbar filter menu that used to back this type (and offered `.none`/
/// `.spentOnly` too) was removed (issue #92 follow-up): all three tabs now
/// share the same chrome, with no per-tab filter menu.
nonisolated enum TransactionFilterOption: String, CaseIterable {
    case exceededOnly
    case excludedOnly

    var label: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .exceededOnly: return String(localized: "Exceeded only", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .excludedOnly: return String(localized: "Excluded only", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }
}

/// Mirrors web's `matchesSearch` (`transactionsPanel/helpers.ts`) — the only
/// predicate the Fixed and Payments tabs need now that their legacy filter
/// menu is gone; Variable's own filtering lives in `VariableQuickFiltering`.
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
        searchQuery: String,
        categoryName: (Int32) -> String?,
        ownerName: (String) -> String?
    ) -> [Wellspent_V1_Transaction] {
        transactions.filter { transaction in
            matchesSearch(
                name: transaction.name,
                categoryName: categoryName(transaction.categoryID),
                ownerName: ownerName(transaction.paymentMethodID),
                query: searchQuery
            )
        }
    }
}
