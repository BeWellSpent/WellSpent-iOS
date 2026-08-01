import WellSpentAPI

/// Pure actual-spend derivation for the Expense Overview tab, mirroring web's
/// `computeActualTotals`/`isTransactionExcluded` (WellSpent-web/src/components/
/// budget/{expensesPanel,transactionsPanel}/helpers.ts). Kept free of
/// network/view-model state so it's directly testable.
nonisolated enum ExpenseOverviewCalculations {
    struct ActualTotals {
        var byCategory: [Int32: (units: Int64, nanos: Int32)] = [:]
        var byCategoryPerson: [Int32: [Int64: (units: Int64, nanos: Int32)]] = [:]
        var uncategorized: (units: Int64, nanos: Int32) = (0, 0)
    }

    /// A transaction is excluded from totals if manually flagged, or if its
    /// category is the system "Income" category — regardless of the flag
    /// (docs/features/transactions.md).
    static func isTransactionExcluded(_ transaction: Wellspent_V1_Transaction, incomeCategoryID: Int32?) -> Bool {
        transaction.isExcluded || (incomeCategoryID != nil && transaction.categoryID == incomeCategoryID)
    }

    /// Fixed-type transaction type ID, matching `FixedExpensesViewModel.fixedTypeID`
    /// (transaction_type lookup table seed order: Fixed = 1).
    private static let fixedTypeID: Int32 = 1

    /// Sums transactions into per-category and per-(category, person) actual
    /// totals. Excluded transactions are dropped entirely; unpaid Fixed-type
    /// transactions don't count as actual spend yet; transactions with no
    /// category accumulate into `uncategorized` rather than being dropped.
    /// A transaction is attributed to a person via its payment method's
    /// `budgetPersonID` (0 = unattributed) — `paymentMethodPersonMap` maps
    /// payment method ID to that person ID.
    static func computeActualTotals(
        transactions: [Wellspent_V1_Transaction],
        paymentMethodPersonMap: [String: Int64],
        incomeCategoryID: Int32?
    ) -> ActualTotals {
        var totals = ActualTotals()

        for transaction in transactions {
            if isTransactionExcluded(transaction, incomeCategoryID: incomeCategoryID) { continue }
            if transaction.transactionTypeID == fixedTypeID && !transaction.isPaid { continue }

            let amount = (units: transaction.amount.units, nanos: transaction.amount.nanos)
            let personID = paymentMethodPersonMap[transaction.paymentMethodID] ?? 0

            guard transaction.categoryID != 0 else {
                totals.uncategorized = TransactionAmountFormatting.sum([totals.uncategorized, amount])
                continue
            }

            totals.byCategory[transaction.categoryID] = TransactionAmountFormatting.sum([
                totals.byCategory[transaction.categoryID] ?? (0, 0), amount
            ])
            var personTotals = totals.byCategoryPerson[transaction.categoryID] ?? [:]
            personTotals[personID] = TransactionAmountFormatting.sum([personTotals[personID] ?? (0, 0), amount])
            totals.byCategoryPerson[transaction.categoryID] = personTotals
        }

        return totals
    }

    static func isOver(actual: (units: Int64, nanos: Int32), planned: (units: Int64, nanos: Int32)) -> Bool {
        let plannedValue = Double(planned.units) + Double(planned.nanos) / 1_000_000_000
        guard plannedValue > 0 else { return false }
        let actualValue = Double(actual.units) + Double(actual.nanos) / 1_000_000_000
        return actualValue > plannedValue
    }
}
