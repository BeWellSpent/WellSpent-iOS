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

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
            && !isSubmitting
    }

    init(expense: Wellspent_V1_FixedExpense, currencyCode: String, authenticatedClient: ProtocolClient) {
        self.expenseID = expense.id
        self.budgetProfileID = expense.budgetProfileID
        self.currencyCode = currencyCode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)

        name = expense.name
        amountText = MoneyInput.formatForEditing(units: expense.plannedAmount.units, nanos: expense.plannedAmount.nanos)
        startDate = expense.hasAnchorDate ? expense.anchorDate.dateOnly : Date()
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
        let request = Wellspent_V1_UpdateFixedExpenseRequest.with {
            $0.id = expenseID
            $0.budgetProfileID = budgetProfileID
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.plannedAmount = money
            $0.categoryID = categoryID
            $0.paymentMethodID = paymentMethodID
            $0.anchorDate = Google_Protobuf_Timestamp(dateOnly: startDate)
            $0.dayOfMonth = FixedExpenseScheduling.dayOfMonth(for: startDate)
            $0.dayOfWeek = FixedExpenseScheduling.dayOfWeek(for: startDate)
            $0.frequencyUnit = frequencyUnit
            $0.intervalMonths = Int32(intervalMonths)
            $0.intervalWeeks = Int32(intervalWeeks)
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
