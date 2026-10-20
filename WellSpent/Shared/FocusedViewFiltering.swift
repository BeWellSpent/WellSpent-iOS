import Foundation
import WellSpentAPI

/// Focused View's ownership rule: mine, or unattributed (0) — never someone else's.
enum FocusedViewFiltering {
    static func isMineOrUnattributed(_ personID: Int64, myPersonID: Int64?) -> Bool {
        personID == 0 || personID == myPersonID
    }

    /// The person a payment method belongs to, or `nil` for cash / an
    /// unattributed method — the shared resolution Transaction.paymentMethodID
    /// and FixedExpense.paymentMethodID both go through.
    static func ownerID(paymentMethodID: String, paymentMethods: [Wellspent_V1_PaymentMethod]) -> Int64? {
        guard !paymentMethodID.isEmpty,
              let method = paymentMethods.first(where: { $0.id == paymentMethodID }),
              method.budgetPersonID != 0 else { return nil }
        return method.budgetPersonID
    }
}
