import Foundation
import WellSpentAPI

/// Pure math for splitting a purchase into card installments.
///
/// Mirrors `installmentAmount`/`installmentEndDate` in the backend's
/// `internal/service/installment_plan.go` and `installmentPlan.ts` on web. This
/// is the one duplication the feature accepts: the sheet has to show what each
/// payment will be *before* anything exists to ask the server about. Everything
/// shown after creation comes from the server's response, so drift can only
/// ever reach the preview — but change the three together.
nonisolated enum InstallmentPlan {
    static let minPayments: Int32 = 2
    static let maxPayments: Int32 = 120

    /// A purchase split evenly across `payments`, rounded to the nearest cent.
    ///
    /// A fixed expense carries ONE planned amount that every payment inherits,
    /// so an uneven total cannot be balanced by a larger final payment the way
    /// a card issuer does it. $1,000 over 3 is $333.33 x 3 = $999.99, and that
    /// residue is structural rather than a rounding bug.
    ///
    /// Works in whole cents on Int64 rather than through a Double, matching the
    /// backend's big.Int path — most cent amounts are not exactly representable
    /// in binary floating point.
    static func amount(
        total: (units: Int64, nanos: Int32),
        payments: Int32
    ) -> (units: Int64, nanos: Int32) {
        guard payments >= 1 else { return (0, 0) }
        let totalCents = total.units * 100 + Int64(total.nanos) / 10_000_000
        let n = Int64(payments)
        let q = totalCents / n
        let r = totalCents % n
        // Round halves away from zero, so an exact half-cent lands on the
        // larger magnitude rather than silently favouring one direction.
        var cents = q
        if abs(r) * 2 >= n {
            cents += totalCents < 0 ? -1 : 1
        }
        return (units: cents / 100, nanos: Int32(cents % 100) * 10_000_000)
    }

    /// Default first payment: the same day of the month as the purchase, one
    /// month later. A card charges the statement after the one you bought in,
    /// so a purchase in August is first billed in September.
    static func defaultFirstPayment(purchase: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 1, to: purchase) ?? purchase
    }

    /// Date of the LAST payment — the first payment plus one month per
    /// remaining payment. Off by one here would spawn a whole extra payment.
    static func endDate(firstPayment: Date, payments: Int32, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: Int(max(payments - 1, 0)), to: firstPayment) ?? firstPayment
    }

    /// Payment count implied by an end date, so the two fields can be edited
    /// either way — the same bidirectional link the Add/Edit Fixed Expense
    /// forms already use.
    static func payments(firstPayment: Date, endDate: Date, calendar: Calendar = .current) -> Int32 {
        let months = calendar.dateComponents([.month], from: firstPayment, to: endDate).month ?? 0
        return Int32(max(months + 1, 1))
    }

    /// Whether a row can be split. Mirrors the backend's guards in
    /// `CreateInstallmentPlan`, so the action isn't offered where the RPC would
    /// refuse it: a Fixed transaction is already the recurring thing this would
    /// create, a converted one can't be converted twice, and a negative amount
    /// is money received.
    static func canSplit(_ transaction: Wellspent_V1_Transaction) -> Bool {
        guard transaction.transactionTypeID != 1 else { return false }
        guard transaction.installmentFixedExpenseID.isEmpty else { return false }
        return !TransactionAmountFormatting.isReceived(
            units: transaction.amount.units,
            nanos: transaction.amount.nanos
        ) && (transaction.amount.units != 0 || transaction.amount.nanos != 0)
    }
}
