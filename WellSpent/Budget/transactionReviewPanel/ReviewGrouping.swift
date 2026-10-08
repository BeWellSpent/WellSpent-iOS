import WellSpentAPI

struct ReviewGroup: Identifiable {
    let matchedTransactionID: String
    let matchedTransactionName: String
    let matchedTransactionPersonID: Int64
    let reviews: [Wellspent_V1_TransactionReview]
    var id: String { matchedTransactionID }
}

/// Groups pending reviews by matched (fixed) transaction — a split match shows as one row.
nonisolated enum ReviewGrouping {
    static func group(_ reviews: [Wellspent_V1_TransactionReview]) -> [ReviewGroup] {
        var order: [String] = []
        var byMatched: [String: [Wellspent_V1_TransactionReview]] = [:]
        for review in reviews {
            let key = review.matchedTransactionID
            if byMatched[key] == nil {
                order.append(key)
                byMatched[key] = []
            }
            byMatched[key]?.append(review)
        }
        return order.compactMap { key in
            guard let group = byMatched[key], let first = group.first else { return nil }
            return ReviewGroup(
                matchedTransactionID: key,
                matchedTransactionName: first.matchedTransactionName,
                matchedTransactionPersonID: first.matchedTransactionPersonID,
                reviews: group
            )
        }
    }
}
