import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

/// Settles a payment plan's remaining balance in one payment — any fixed
/// expense with `totalPayments` set, not only installment plans created from
/// a transaction. Never touches `endDate`; the backend handles that.
@MainActor
@Observable
final class PayFixedExpenseInFullViewModel {
    private static let logger = AppLogger.logger("FixedExpenses")

    /// Pre-filled from the fixed expense's `remainingBalance`, but always
    /// user-editable — a real payoff figure usually differs from the
    /// arithmetic (interest, fees, early-settlement discounts).
    var amountText: String
    var paidDate = Date()
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let budgetProfileID: String
    private let fixedExpenseID: String
    private let currencyCode: String
    private let restClient: WellSpentREST.Client

    var canSubmit: Bool {
        MoneyInput.parseAmount(amountText) != nil && !isSubmitting
    }

    init(budgetProfileID: String, fixedExpenseID: String, currencyCode: String, remainingBalance: Wellspent_V1_Money, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.fixedExpenseID = fixedExpenseID
        self.currencyCode = currencyCode
        self.restClient = restClient
        amountText = MoneyInput.formatForEditing(units: remainingBalance.units, nanos: remainingBalance.nanos)
    }

    func submit() async -> (transaction: Wellspent_V1_Transaction, fixedExpense: Wellspent_V1_FixedExpense)? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let money = Wellspent_V1_Money.with {
            $0.units = amount.units
            $0.nanos = amount.nanos
            $0.currency = currencyCode
        }
        let fallback = "Couldn't pay off that fixed expense."
        Self.logger.info("paying off fixed expense in full fixedExpenseID=\(self.fixedExpenseID, privacy: .public)")

        do {
            let output = try await restClient.payFixedExpenseInFull(.init(
                path: .init(id: budgetProfileID, feId: fixedExpenseID),
                body: .json(.init(
                    amount: BudgetRESTMapping.restMoney(from: money),
                    paidDate: Google_Protobuf_Timestamp(dateOnly: paidDate).restDateString
                ))
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                Self.logger.error("pay in full failed fixedExpenseID=\(self.fixedExpenseID, privacy: .public)")
                return nil
            }
            Self.logger.info("pay in full succeeded fixedExpenseID=\(self.fixedExpenseID, privacy: .public)")
            return (BudgetRESTMapping.transaction(from: body.transaction), BudgetRESTMapping.fixedExpense(from: body.fixedExpense))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            Self.logger.error("pay in full failed fixedExpenseID=\(self.fixedExpenseID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
