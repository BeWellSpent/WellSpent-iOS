import Foundation
import WellSpentAPI

/// Quick-filter chips for the Variable tab (issue #92) — distinct from
/// `TransactionFilterOption`, which the Fixed/Payments tabs no longer use at
/// all (their legacy toolbar filter menu was removed). `exceededOnly`/
/// `excludedOnly` are real, server-backed filters applied as their own
/// independent toggle chips in the same row (not part of this enum's radio
/// group) — see `TransactionsListView.quickFilterToggleChip`.
nonisolated enum VariableQuickFilter: String, CaseIterable, Identifiable {
    case all
    case moneyOut
    case moneyIn
    case needsReview

    var id: String { rawValue }

    var label: String {
        let locale = AppLanguageStore.currentLocale
        let bundle = AppLanguageStore.currentBundle
        switch self {
        case .all: return String(localized: "All", bundle: bundle, locale: locale)
        case .moneyOut: return String(localized: "Money Out", bundle: bundle, locale: locale)
        case .moneyIn: return String(localized: "Money In", bundle: bundle, locale: locale)
        case .needsReview: return String(localized: "Needs review", bundle: bundle, locale: locale)
        }
    }
}

nonisolated enum VariableQuickFiltering {
    /// Uncategorized, or queued with a pending (unconfirmed) fixed-expense
    /// match — the same two things that already produce a visible hint on
    /// the row (a missing category chip caption, or "(linked to X)").
    static func needsReview(
        _ transaction: Wellspent_V1_Transaction,
        categoryName: (Int32) -> String?,
        hasPendingMatch: (Wellspent_V1_Transaction) -> Bool
    ) -> Bool {
        categoryName(transaction.categoryID) == nil || hasPendingMatch(transaction)
    }

    static func matches(
        _ transaction: Wellspent_V1_Transaction,
        filter: VariableQuickFilter,
        categoryName: (Int32) -> String?,
        hasPendingMatch: (Wellspent_V1_Transaction) -> Bool
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .moneyOut:
            return !TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
        case .moneyIn:
            return TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
        case .needsReview:
            return needsReview(transaction, categoryName: categoryName, hasPendingMatch: hasPendingMatch)
        }
    }

    /// Applies the quick filter plus the two independent toggle chips
    /// (`exceededOnly`/`excludedOnly`, carried forward from
    /// `TransactionFilterOption`) plus search — the Variable tab's full
    /// predicate chain.
    static func apply(
        _ transactions: [Wellspent_V1_Transaction],
        filter: VariableQuickFilter,
        exceededOnly: Bool,
        excludedOnly: Bool,
        searchQuery: String,
        incomeCategoryID: Int32?,
        overBudgetTransactionIDs: Set<String>,
        categoryName: (Int32) -> String?,
        ownerName: (String) -> String?,
        hasPendingMatch: (Wellspent_V1_Transaction) -> Bool
    ) -> [Wellspent_V1_Transaction] {
        transactions.filter { transaction in
            guard matches(transaction, filter: filter, categoryName: categoryName, hasPendingMatch: hasPendingMatch) else { return false }
            if exceededOnly && !overBudgetTransactionIDs.contains(transaction.id) { return false }
            if excludedOnly && !ExpenseOverviewCalculations.isTransactionExcluded(transaction, incomeCategoryID: incomeCategoryID) { return false }
            return TransactionFiltering.matchesSearch(
                name: transaction.name,
                categoryName: categoryName(transaction.categoryID),
                ownerName: ownerName(transaction.paymentMethodID),
                query: searchQuery
            )
        }
    }

    /// Count for the "Needs review" chip's badge — computed against the
    /// currently-loaded (not yet quick-filtered) list, so it always reads the
    /// same regardless of which chip is active.
    static func needsReviewCount(
        _ transactions: [Wellspent_V1_Transaction],
        categoryName: (Int32) -> String?,
        hasPendingMatch: (Wellspent_V1_Transaction) -> Bool
    ) -> Int {
        transactions.filter { needsReview($0, categoryName: categoryName, hasPendingMatch: hasPendingMatch) }.count
    }
}
