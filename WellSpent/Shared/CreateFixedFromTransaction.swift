import Foundation
import WellSpentAPI

/// Whether a variable transaction can become a recurring fixed expense.
/// Mirrors `InstallmentPlan.canSplit`'s guards — this is the same family of
/// action, just a different destination.
nonisolated enum CreateFixedFromTransaction {
    static func canCreate(_ transaction: Wellspent_V1_Transaction) -> Bool {
        guard transaction.transactionTypeID != 1 else { return false }
        guard transaction.installmentFixedExpenseID.isEmpty else { return false }
        return !TransactionAmountFormatting.isReceived(
            units: transaction.amount.units,
            nanos: transaction.amount.nanos
        ) && (transaction.amount.units != 0 || transaction.amount.nanos != 0)
    }
}
