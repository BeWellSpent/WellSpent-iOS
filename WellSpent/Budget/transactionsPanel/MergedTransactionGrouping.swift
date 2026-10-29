import Foundation
import WellSpentAPI

/// Splits a period's Variable+Fixed transactions for the merged Transactions
/// sub-tab (Stage 2 of docs/features/overview-plan-navigation-rework.md):
/// unpaid Fixed bills float to a dedicated section at the top — the thing a
/// user most needs to see — and everything else (paid Fixed rows and all
/// Variable rows) interleaves into one day-grouped chronological list below.
nonisolated enum MergedTransactionGrouping {
    struct Partition {
        /// Soonest due first — a schedule, read top to bottom, same
        /// ordering convention `FixedExpensesListView` used for its own
        /// Unpaid section before this merge.
        let unpaidFixed: [Wellspent_V1_Transaction]
        /// Paid Fixed rows + all Variable rows, unsorted here — callers
        /// day-group this via `TransactionDayGrouping.group(_:)`.
        let rest: [Wellspent_V1_Transaction]
    }

    static func partition(_ transactions: [Wellspent_V1_Transaction], fixedTypeID: Int32) -> Partition {
        let isUnpaidFixed: (Wellspent_V1_Transaction) -> Bool = {
            $0.transactionTypeID == fixedTypeID && !$0.isPaid
        }
        let unpaidFixed = transactions
            .filter(isUnpaidFixed)
            .sorted { lhs, rhs in
                if lhs.date.dateOnly != rhs.date.dateOnly { return lhs.date.dateOnly < rhs.date.dateOnly }
                return lhs.id < rhs.id
            }
        let rest = transactions.filter { !isUnpaidFixed($0) }
        return Partition(unpaidFixed: unpaidFixed, rest: rest)
    }

    /// Whether `transaction` passes the Variable-only quick-filter radio
    /// (All/Money Out/Money In/Needs review). A Fixed row always passes All,
    /// Money Out and Needs review — received/spent sign-flip and a pending
    /// Plaid match are Variable-only concepts a scheduled bill never carries,
    /// so filtering by them would make a bill disappear for a reason that has
    /// nothing to do with it. Money In is the one exception: a Fixed row is
    /// never actually received money (it's always shown as a plain positive
    /// amount, never through the Spent/Received sign convention), so it must
    /// fail that filter rather than unconditionally pass it (issue #96).
    static func passesVariableOnlyFilter(
        _ transaction: Wellspent_V1_Transaction,
        fixedTypeID: Int32,
        filter: VariableQuickFilter,
        categoryName: (Int32) -> String?,
        hasPendingMatch: (Wellspent_V1_Transaction) -> Bool
    ) -> Bool {
        guard transaction.transactionTypeID != fixedTypeID else { return filter != .moneyIn }
        return VariableQuickFiltering.matches(transaction, filter: filter, categoryName: categoryName, hasPendingMatch: hasPendingMatch)
    }

    /// The merged list's full predicate chain for the "rest" (chronological)
    /// section — the quick-filter radio (Fixed rows always pass, see above),
    /// the Exceeded/Excluded toggle chips (type-agnostic, apply to both
    /// kinds), and search. Mirrors `VariableQuickFiltering.apply`, swapping
    /// in `passesVariableOnlyFilter` for the plain `.matches` call.
    static func applyFilters(
        _ transactions: [Wellspent_V1_Transaction],
        fixedTypeID: Int32,
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
            guard passesVariableOnlyFilter(
                transaction,
                fixedTypeID: fixedTypeID,
                filter: filter,
                categoryName: categoryName,
                hasPendingMatch: hasPendingMatch
            ) else { return false }
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
}
