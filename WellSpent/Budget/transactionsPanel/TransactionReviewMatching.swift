import WellSpentAPI

/// Pure derivations from a budget's `TransactionReview` list, shared by the
/// Variable and Fixed transaction lists. Mirrors web's inline computation in
/// `TransactionsPanel.tsx` (`confirmedReviewVariableTxIds`,
/// `linkedVariableByFixedTxId`) and `helpers.ts`'s `buildPendingReviewMatchMap`.
nonisolated enum TransactionReviewMatching {
    /// Variable transactions whose review was confirmed — hidden from the
    /// Variable list and shown instead as a linked sub-row under the
    /// matched Fixed transaction.
    static func confirmedTransactionIDs(_ reviews: [Wellspent_V1_TransactionReview]) -> Set<String> {
        Set(reviews.filter { $0.status == "confirmed" }.map(\.transactionID))
    }

    /// The matched Fixed transaction's name, for a Variable transaction with
    /// a still-pending (not yet confirmed) review — shown as an inline hint.
    static func pendingMatchName(forTransactionID transactionID: String, reviews: [Wellspent_V1_TransactionReview]) -> String? {
        reviews.first { $0.status == "pending" && $0.transactionID == transactionID }?.matchedTransactionName
    }

    /// Confirmed reviews matched to this Fixed transaction — each carries its
    /// own denormalized `transactionName`/`transactionAmount`, so no separate
    /// fetch of the underlying (excluded) Variable transaction is needed to
    /// render the linked sub-row.
    static func linkedReviews(forFixedTransactionID fixedTransactionID: String, reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_TransactionReview] {
        reviews.filter { $0.status == "confirmed" && $0.matchedTransactionID == fixedTransactionID }
    }
}
