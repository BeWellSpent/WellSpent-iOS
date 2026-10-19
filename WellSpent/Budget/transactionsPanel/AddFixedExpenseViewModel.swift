import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AddFixedExpenseViewModel {
    private static let logger = AppLogger.logger("FixedExpenses")

    var name = ""
    var amountText = ""
    private(set) var startDate = Date()
    private(set) var frequencyUnit: Wellspent_V1_FrequencyUnit = .month
    private(set) var intervalMonths = 1
    private(set) var intervalWeeks = 1
    var categoryID: Int32 = 0
    var paymentMethodID = ""

    /// Payment plan (optional): number-of-payments and end-date are kept in
    /// sync via `FixedExpenseScheduling`'s bidirectional math, mirroring
    /// web's `AddTransactionModal` `recalcEndDate`/`handleEndDateChange`.
    /// Deliberately plain stored properties with no `didSet` — all mutation
    /// goes through the explicit `handle*` methods below, one per input,
    /// same shape as web's per-field `onChange` handlers. A `didSet` on both
    /// `paymentsText` and `endDate` that each recompute the other would
    /// re-enter on every edit-date pick and silently "snap" the user's exact
    /// picked date to the nearest interval boundary instead of keeping what
    /// they chose. `endDate` is `nil` when unset — an indefinite (non
    /// -payment-plan) fixed expense.
    private(set) var paymentsText = ""
    private(set) var endDate: Date?

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let budgetProfileID: String
    private let currencyCode: String
    private let restClient: WellSpentREST.Client

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
            && !isSubmitting
    }

    init(budgetProfileID: String, currencyCode: String, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.restClient = restClient
    }

    func setStartDate(_ value: Date) {
        startDate = value
        recalcEndDateIfNeeded()
    }

    func setFrequencyUnit(_ value: Wellspent_V1_FrequencyUnit) {
        frequencyUnit = value
        recalcEndDateIfNeeded()
    }

    func setIntervalMonths(_ value: Int) {
        intervalMonths = value
        recalcEndDateIfNeeded()
    }

    func setIntervalWeeks(_ value: Int) {
        intervalWeeks = value
        recalcEndDateIfNeeded()
    }

    func handlePaymentsTextChange(_ newText: String) {
        paymentsText = newText
        guard let payments = Int(newText), payments > 0 else {
            if newText.isEmpty { endDate = nil }
            return
        }
        endDate = FixedExpenseScheduling.endDate(fromTotalPayments: payments, anchor: startDate, frequencyUnit: frequencyUnit, intervalMonths: intervalMonths, intervalWeeks: intervalWeeks)
    }

    func handleEndDateChange(_ newDate: Date?) {
        endDate = newDate
        guard let newDate else {
            paymentsText = ""
            return
        }
        paymentsText = String(FixedExpenseScheduling.totalPayments(fromEndDate: newDate, anchor: startDate, frequencyUnit: frequencyUnit, intervalMonths: intervalMonths, intervalWeeks: intervalWeeks))
    }

    private func recalcEndDateIfNeeded() {
        guard let payments = Int(paymentsText), payments > 0 else { return }
        endDate = FixedExpenseScheduling.endDate(fromTotalPayments: payments, anchor: startDate, frequencyUnit: frequencyUnit, intervalMonths: intervalMonths, intervalWeeks: intervalWeeks)
    }

    func submit() async -> (expense: Wellspent_V1_FixedExpense, transaction: Wellspent_V1_Transaction)? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let money = Wellspent_V1_Money.with {
            $0.units = amount.units
            $0.nanos = amount.nanos
            $0.currency = currencyCode
        }
        let anchorTimestamp = Google_Protobuf_Timestamp(dateOnly: startDate)
        let totalPayments = Int32(paymentsText) ?? 0
        let fallback = "Couldn't create that fixed expense."
        Self.logger.info("creating fixed expense name=\(self.name, privacy: .public) hasPaymentPlan=\(self.endDate != nil, privacy: .public) totalPayments=\(totalPayments, privacy: .public)")

        do {
            let output = try await restClient.createFixedExpense(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(
                    name: name.trimmingCharacters(in: .whitespaces),
                    plannedAmount: BudgetRESTMapping.restMoney(from: money),
                    categoryId: categoryID,
                    paymentMethodId: paymentMethodID,
                    dayOfMonth: FixedExpenseScheduling.dayOfMonth(for: startDate),
                    intervalMonths: Int32(intervalMonths),
                    anchorDate: anchorTimestamp.restDateString,
                    frequencyUnit: BudgetRESTMapping.restFrequencyUnit(from: frequencyUnit),
                    intervalWeeks: Int32(intervalWeeks),
                    dayOfWeek: FixedExpenseScheduling.dayOfWeek(for: startDate),
                    endDate: endDate.map { Google_Protobuf_Timestamp(dateOnly: $0).restDateString },
                    totalPayments: totalPayments
                ))
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                Self.logger.error("create fixed expense failed")
                return nil
            }
            let expense = BudgetRESTMapping.fixedExpense(from: body.fixedExpense)
            let transaction = body.transaction.map(BudgetRESTMapping.transaction(from:)) ?? .init()
            Self.logger.info("create fixed expense succeeded fixedExpenseID=\(expense.id, privacy: .public)")
            return (expense, transaction)
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            Self.logger.error("create fixed expense failed error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
