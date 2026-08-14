import Foundation
import WellSpentAPI

/// What a budget must already have before a transaction can be created.
///
/// Mirrors web's `needsPaymentMethodSetup` in
/// `transactionsPanel/helpers.ts` — kept pure so the rule is testable
/// without a view or a network call.
nonisolated enum TransactionPrerequisites {
    /// A payment method is the one prerequisite the user creates themselves:
    /// system categories always exist and the owner is auto-added as a
    /// person. Both `AddEditTransactionViewModel` and
    /// `AddFixedExpenseViewModel` require one to submit, so with none the
    /// form can be filled in completely and still refuse to save.
    ///
    /// False while the list is still loading — a gate shown on incomplete
    /// data reads as a bug to someone who does have payment methods.
    static func needsPaymentMethod(
        paymentMethods: [Wellspent_V1_PaymentMethod],
        isLoading: Bool
    ) -> Bool {
        if isLoading { return false }
        return paymentMethods.isEmpty
    }
}
