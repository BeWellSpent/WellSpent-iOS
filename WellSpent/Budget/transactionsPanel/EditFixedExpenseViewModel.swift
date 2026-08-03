import Foundation
import Observation
import WellSpentAPI

/// Kept separate from `AddFixedExpenseViewModel` — same field shape, but
/// edit submits `UpdateFixedExpense` against an existing template id rather
/// than creating a new one, and prefills from a `Wellspent_V1_FixedExpense`
/// instead of starting blank.
@MainActor
@Observable
final class EditFixedExpenseViewModel {
    var name: String
    var amountText: String
    var startDate: Date
    var frequencyUnit: Wellspent_V1_FrequencyUnit
    var intervalMonths: Int
    var intervalWeeks: Int
    var categoryID: Int32
    var paymentMethodID: String

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
        }
        if shouldSendAnchorDate {
            request.anchorDate = Google_Protobuf_Timestamp(dateOnly: startDate)
        }
        let response = await client.updateFixedExpense(request: request)

        switch response.result {
        case .success(let message):
            return message.expense
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that fixed expense."
            return nil
        }
    }
}
