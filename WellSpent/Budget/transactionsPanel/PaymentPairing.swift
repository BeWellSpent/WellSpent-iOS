import Foundation
import WellSpentAPI

/// Folds the two Payment-category rows of one card payment into a single group: the
/// outflow from the paying account and the matching inflow on the card. Plaid sends no
/// shared identifier for these (every imported row has an empty `payment_meta`
/// reference), so the match is: equal and opposite amount, different payment methods,
/// dates within `windowDays`. Each row joins at most one pair; an unmatched row is its
/// own group.
nonisolated enum PaymentPairing {
    static let windowDays = 5

    struct Group: Identifiable {
        let id: String
        /// The outflow first, then the inflow; a single element when nothing matched.
        let transactions: [Wellspent_V1_Transaction]

        var isPair: Bool { transactions.count == 2 }
        /// The row that stands for the group in day grouping and search: the money leaving.
        var representative: Wellspent_V1_Transaction { transactions[0] }
        var isExcluded: Bool { transactions.contains { $0.isExcluded } }

        /// What was paid, counted once: a pair is one payment, not two cancelling rows.
        var paidAmount: (units: Int64, nanos: Int32) {
            let amount = TransactionAmountFormatting.tuple(from: representative.amount)
            return TransactionAmountFormatting.isReceived(units: amount.units, nanos: amount.nanos)
                ? (units: -amount.units, nanos: -amount.nanos)
                : amount
        }
    }

    /// `methodName` resolves a payment method id to its display name, only to break ties
    /// using the "ending in 1234" some banks put in the description.
    static func group(_ transactions: [Wellspent_V1_Transaction], methodName: (String) -> String? = { _ in nil }) -> [Group] {
        let outflows = transactions.filter { isOutflow($0) }
        let inflows = transactions.filter { isInflow($0) }

        struct Candidate { let out: Wellspent_V1_Transaction; let into: Wellspent_V1_Transaction; let maskMismatch: Int; let days: Int }
        var candidates: [Candidate] = []
        for out in outflows {
            let digits = endingDigits(in: out.name)
            for into in inflows where isMirror(out, into) {
                let days = abs(dayDistance(out, into))
                guard days <= windowDays else { continue }
                let mismatch = digits.map { methodName(into.paymentMethodID)?.contains($0) == true ? 0 : 1 } ?? 0
                candidates.append(Candidate(out: out, into: into, maskMismatch: mismatch, days: days))
            }
        }
        candidates.sort { ($0.maskMismatch, $0.days, $0.out.id, $0.into.id) < ($1.maskMismatch, $1.days, $1.out.id, $1.into.id) }

        var partnerOfOutflow: [String: Wellspent_V1_Transaction] = [:]
        var paired: Set<String> = []
        for candidate in candidates where !paired.contains(candidate.out.id) && !paired.contains(candidate.into.id) {
            partnerOfOutflow[candidate.out.id] = candidate.into
            paired.insert(candidate.out.id)
            paired.insert(candidate.into.id)
        }

        var groups: [Group] = []
        var emitted: Set<String> = []
        for transaction in transactions where !emitted.contains(transaction.id) {
            if let partner = partnerOfOutflow[transaction.id] {
                groups.append(Group(id: "\(transaction.id)|\(partner.id)", transactions: [transaction, partner]))
                emitted.insert(partner.id)
            } else if let outflow = outflows.first(where: { partnerOfOutflow[$0.id]?.id == transaction.id }) {
                groups.append(Group(id: "\(outflow.id)|\(transaction.id)", transactions: [outflow, transaction]))
                emitted.insert(outflow.id)
            } else {
                groups.append(Group(id: transaction.id, transactions: [transaction]))
            }
            emitted.insert(transaction.id)
        }
        return groups
    }

    private static func isOutflow(_ t: Wellspent_V1_Transaction) -> Bool {
        let a = TransactionAmountFormatting.tuple(from: t.amount)
        return !TransactionAmountFormatting.isReceived(units: a.units, nanos: a.nanos) && (a.units != 0 || a.nanos != 0)
    }

    private static func isInflow(_ t: Wellspent_V1_Transaction) -> Bool {
        let a = TransactionAmountFormatting.tuple(from: t.amount)
        return TransactionAmountFormatting.isReceived(units: a.units, nanos: a.nanos)
    }

    private static func isMirror(_ out: Wellspent_V1_Transaction, _ into: Wellspent_V1_Transaction) -> Bool {
        let a = TransactionAmountFormatting.tuple(from: out.amount)
        let b = TransactionAmountFormatting.tuple(from: into.amount)
        return a.units == -b.units && a.nanos == -b.nanos && out.paymentMethodID != into.paymentMethodID
    }

    private static func dayDistance(_ a: Wellspent_V1_Transaction, _ b: Wellspent_V1_Transaction) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: a.date.dateOnly)
        let to = calendar.startOfDay(for: b.date.dateOnly)
        return calendar.dateComponents([.day], from: from, to: to).day ?? Int.max
    }

    /// "Payment to Chase card ending in 9967" -> "9967".
    private static func endingDigits(in name: String) -> String? {
        guard let range = name.range(of: #"ending in (\d{3,4})"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(name[range])
        return String(match.suffix(while: { $0.isNumber }))
    }
}

private extension String {
    func suffix(while predicate: (Character) -> Bool) -> Substring {
        var start = endIndex
        while start > startIndex, predicate(self[index(before: start)]) { start = index(before: start) }
        return self[start...]
    }
}
