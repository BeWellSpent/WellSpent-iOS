import Foundation
import Observation
import os
import WellSpentAPI

/// Kept separate from `AddFixedExpenseViewModel` — same field shape, but
/// edit submits `UpdateFixedExpense` against an existing template id rather
/// than creating a new one, and prefills from a `Wellspent_V1_FixedExpense`
/// instead of starting blank.
@MainActor
@Observable
final class EditFixedExpenseViewModel {
    private static let logger = AppLogger.logger("FixedExpenses")

    var name: String
    var amountText: String
    private(set) var startDate: Date
    private(set) var frequencyUnit: Wellspent_V1_FrequencyUnit
    private(set) var intervalMonths: Int
    private(set) var intervalWeeks: Int
    var categoryID: Int32
    var paymentMethodID: String

    /// See `AddFixedExpenseViewModel`'s payment-plan doc comment — same
    /// explicit-handler-methods design (no `didSet`) to avoid the
    /// paymentsText/endDate re-entrant "snap" issue.
    private(set) var paymentsText: String
    private(set) var endDate: Date?

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let expenseID: String
    private let budgetProfileID: String
    private let currencyCode: String
    private let client: Wellspent_V1_BudgetServiceClient

    /// Whether the template already had an explicit `anchor_date` when this
    /// view model was created, and what `startDate` was initially prefilled
    /// to. Legacy expenses (created before `anchor_date` existed, or without
    /// one set) have neither — `startDate` in that case is a display-only
    /// reconstruction from `day_of_month`/`day_of_week`, not a real stored
    /// value. `submit()` only sends `anchor_date` back to the server if the
    /// expense already had one, or the user actually changed the date field
    /// — otherwise saving an unrelated edit (renaming, category change)
    /// would silently give the template a brand-new anchor_date, which can
    /// reschedule its entire due-month cadence for interval>1 expenses (see
    /// `fixedExpenseAnchor` in the backend's `budget_profile_service.go`).
    /// The saved plan's progress, as the server computed it. Captured at init
    /// rather than recomputed from the form: progress is a fact about the
    /// saved plan, not the draft, so it holds still while the user edits and
    /// updates on save. See `paymentsMadeText`.
    private let savedPaymentsMade: Int32
    private let hadAnchorDate: Bool
    private let initialStartDate: Date

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
            && !isSubmitting
    }

    /// Whether `submit()` will include `anchor_date` in the update request —
    /// exposed so the core bug-fix decision is directly unit-testable
    /// without needing to mock the network call.
    var shouldSendAnchorDate: Bool {
        hadAnchorDate || startDate != initialStartDate
    }

    init(expense: Wellspent_V1_FixedExpense, currencyCode: String, authenticatedClient: ProtocolClient) {
        self.expenseID = expense.id
        self.budgetProfileID = expense.budgetProfileID
        self.currencyCode = currencyCode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)

        name = expense.name
        amountText = MoneyInput.formatForEditing(units: expense.plannedAmount.units, nanos: expense.plannedAmount.nanos)
        savedPaymentsMade = expense.paymentsMade
        hadAnchorDate = expense.hasAnchorDate
        let resolvedStartDate = expense.hasAnchorDate
            ? expense.anchorDate.dateOnly
            : FixedExpenseScheduling.displayDate(
                dayOfMonth: expense.dayOfMonth,
                dayOfWeek: expense.dayOfWeek,
                isWeekly: expense.frequencyUnit == .week
            )
        initialStartDate = resolvedStartDate
        startDate = resolvedStartDate
        frequencyUnit = expense.frequencyUnit == .week ? .week : .month
        intervalMonths = expense.intervalMonths > 0 ? Int(expense.intervalMonths) : 1
        intervalWeeks = expense.intervalWeeks > 0 ? Int(expense.intervalWeeks) : 1
        categoryID = expense.categoryID
        paymentMethodID = expense.paymentMethodID
        paymentsText = expense.totalPayments > 0 ? String(expense.totalPayments) : ""
        endDate = expense.hasEndDate ? expense.endDate.dateOnly : nil
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

    /// "N of M payments made" progress text for the payment-plan section —
    /// `nil` when there's no plan set.
    ///
    /// The count comes from the server (`FixedExpensePaymentsMade`), mirroring
    /// web. It used to be estimated here from the draft's own anchor and
    /// interval, which could not be right for an expense with no `anchor_date`
    /// — the real fallback is `created_at`, which is not on the wire — and
    /// which disagreed with both the transaction row and web (#61).
    var paymentsMadeText: String? {
        guard let totalPayments = Int(paymentsText), totalPayments > 0 else { return nil }
        return "\(savedPaymentsMade) of \(totalPayments) payments made"
    }

    func submit() async -> Wellspent_V1_FixedExpense? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let money = Wellspent_V1_Money.with {
            $0.units = amount.units
            $0.nanos = amount.nanos
            $0.currency = currencyCode
        }
        var request = Wellspent_V1_UpdateFixedExpenseRequest.with {
            $0.id = expenseID
            $0.budgetProfileID = budgetProfileID
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.plannedAmount = money
            $0.categoryID = categoryID
            $0.paymentMethodID = paymentMethodID
            $0.dayOfMonth = FixedExpenseScheduling.dayOfMonth(for: startDate)
            $0.dayOfWeek = FixedExpenseScheduling.dayOfWeek(for: startDate)
            $0.frequencyUnit = frequencyUnit
            $0.intervalMonths = Int32(intervalMonths)
            $0.intervalWeeks = Int32(intervalWeeks)
            // Leaving endDate unset (rather than setting it to a zero
            // value) is what tells the backend to clear it — see
            // `UpdateFixedExpenseRequest.end_date`'s proto comment ("null =
            // clear it") and `internal/handler/budget_handler.go`'s
            // `if req.Msg.EndDate != nil` check.
            if let endDate {
                $0.endDate = Google_Protobuf_Timestamp(dateOnly: endDate)
            }
            $0.totalPayments = Int32(paymentsText) ?? 0
        }
        if shouldSendAnchorDate {
            request.anchorDate = Google_Protobuf_Timestamp(dateOnly: startDate)
        }
        Self.logger.info("updating fixed expense fixedExpenseID=\(self.expenseID, privacy: .public) hasPaymentPlan=\(self.endDate != nil, privacy: .public) totalPayments=\(request.totalPayments, privacy: .public)")
        let response = await client.updateFixedExpense(request: request)

        switch response.result {
        case .success(let message):
            Self.logger.info("update fixed expense succeeded fixedExpenseID=\(self.expenseID, privacy: .public)")
            return message.expense
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that fixed expense."
            Self.logger.error("update fixed expense failed fixedExpenseID=\(self.expenseID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
