import WellSpentAPI

/// Splits a category's transactions by the person who paid, for the Expense
/// Overview drill-down.
///
/// Mirrors web's `expenseOverviewPanel/ownerGrouping.ts` deliberately — the two
/// are named to make the pairing obvious, and any change to one belongs in the
/// other. Both must also match the **server's** attribution rule
/// (`computeActuals` in `expense_summary_calculator.go`), because the
/// transactions listed beneath a person have to add up to the actual figure
/// printed beside their name.
nonisolated enum TransactionOwnerGrouping {
    struct Groups {
        /// Transactions belonging to each person who gets a row, by person ID.
        var byPerson: [Int64: [Wellspent_V1_Transaction]]
        /// Everything with no person to sit under — see `group(_:...)`.
        var unclaimed: [Wellspent_V1_Transaction]
    }

    /// The person a transaction belongs to, or `nil` when it belongs to nobody.
    ///
    /// A transaction is credited to a person only when it has a payment method
    /// *and* that method names one. Cash spending, and a method attributed to
    /// nobody, belong to no one — exactly as the server treats them.
    static func ownerID(
        of transaction: Wellspent_V1_Transaction,
        paymentMethods: [Wellspent_V1_PaymentMethod]
    ) -> Int64? {
        guard !transaction.paymentMethodID.isEmpty,
              let method = paymentMethods.first(where: { $0.id == transaction.paymentMethodID }),
              method.budgetPersonID != 0 else { return nil }
        return method.budgetPersonID
    }

    /// Groups `transactions` by owner.
    ///
    /// `renderedPersonIDs` is the set of people who actually get a row — the
    /// summary's `personBreakdowns`. Anything attributed to somebody outside
    /// that set joins `unclaimed`, which is what guarantees **every transaction
    /// appears exactly once**. Two different things land there:
    ///
    /// - spending with no payment method, or one belonging to nobody (cash);
    /// - spending by a person the server omitted from `personBreakdowns`, which
    ///   it does when their planned *and* actual are both zero — so someone
    ///   whose transactions net to exactly zero has no row to sit under.
    ///
    /// Filing either under a person would be worse than a separate group:
    /// neither counts toward anyone's actual total.
    ///
    /// Newest first within a group, matching the Transactions tab's variable
    /// feed. Day headers are deliberately not reproduced here — the person is
    /// the grouping this view is about, and person → day → transaction is a lot
    /// of nesting on a phone.
    static func group(
        _ transactions: [Wellspent_V1_Transaction],
        paymentMethods: [Wellspent_V1_PaymentMethod],
        renderedPersonIDs: Set<Int64>
    ) -> Groups {
        var byPerson: [Int64: [Wellspent_V1_Transaction]] = [:]
        var unclaimed: [Wellspent_V1_Transaction] = []

        for transaction in transactions {
            if let ownerID = ownerID(of: transaction, paymentMethods: paymentMethods),
               renderedPersonIDs.contains(ownerID) {
                byPerson[ownerID, default: []].append(transaction)
            } else {
                unclaimed.append(transaction)
            }
        }

        for key in byPerson.keys {
            byPerson[key] = sortedNewestFirst(byPerson[key] ?? [])
        }
        return Groups(byPerson: byPerson, unclaimed: sortedNewestFirst(unclaimed))
    }

    /// ID breaks the tie so two transactions on the same day keep a stable
    /// order between renders — `date` is a DATE-only value, so ties are common.
    /// Read through `dateOnly`, never the raw timestamp (the v1.15.1 bug class).
    private static func sortedNewestFirst(
        _ transactions: [Wellspent_V1_Transaction]
    ) -> [Wellspent_V1_Transaction] {
        transactions.sorted { lhs, rhs in
            if lhs.date.dateOnly != rhs.date.dateOnly {
                return lhs.date.dateOnly > rhs.date.dateOnly
            }
            return lhs.id < rhs.id
        }
    }
}
