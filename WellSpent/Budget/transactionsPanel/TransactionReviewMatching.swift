import WellSpentAPI

/// Pure derivations from a budget's `TransactionReview` list, shared by the
/// Variable and Fixed transaction lists.
///
/// Issue #97: a confirmed match used to hide the Variable transaction and
/// show it only as a read-only sub-row under the Fixed occurrence — no way
/// to fix a Plaid-miscategorized import once it was linked. Flipped: the
/// Fixed occurrence is what's hidden now (it's redundant once its payment
/// is represented by one or more Variable rows), and each matched Variable
/// transaction renders normally — fully editable — with an expand showing
/// the Fixed bill it settled.
nonisolated enum TransactionReviewMatching {
    /// Fixed transactions with at least one confirmed match — hidden as
    /// their own primary row, since the Variable row(s) that paid them
    /// represent that same event now.
    static func confirmedFixedTransactionIDs(_ reviews: [Wellspent_V1_TransactionReview]) -> Set<String> {
        Set(reviews.filter { $0.status == "confirmed" }.map(\.matchedTransactionID))
    }

    /// The matched Fixed transaction's name, for a Variable transaction with
    /// a still-pending (not yet confirmed) review — shown as an inline hint.
    static func pendingMatchName(forTransactionID transactionID: String, reviews: [Wellspent_V1_TransactionReview]) -> String? {
        reviews.first { $0.status == "pending" && $0.transactionID == transactionID }?.matchedTransactionName
    }

    /// This Variable transaction's confirmed review, if any — gives the
    /// matched Fixed transaction's ID so its real plannedAmount/name can be
    /// looked up for the expand content (the review's own denormalized
    /// fields describe the Variable side, not the Fixed one).
    static func confirmedMatch(forTransactionID transactionID: String, reviews: [Wellspent_V1_TransactionReview]) -> Wellspent_V1_TransactionReview? {
        reviews.first { $0.status == "confirmed" && $0.transactionID == transactionID }
    }
}
