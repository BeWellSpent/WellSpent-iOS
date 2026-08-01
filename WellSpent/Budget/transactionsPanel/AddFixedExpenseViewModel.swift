import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class AddFixedExpenseViewModel {
    var name = ""
    var amountText = ""
    var startDate = Date()
    var frequencyUnit: Wellspent_V1_FrequencyUnit = .month
    var intervalMonths = 1
    var intervalWeeks = 1
    var categoryID: Int32 = 0
    var paymentMethodID = ""

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let budgetProfileID: String
    private let currencyCode: String
    private let client: Wellspent_V1_BudgetServiceClient

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
            && !isSubmitting
    }

    init(budgetProfileID: String, currencyCode: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
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
        let request = Wellspent_V1_CreateFixedExpenseRequest.with {
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
        let response = await client.createFixedExpense(request: request)

        switch response.result {
        case .success(let message):
            return (message.expense, message.transaction)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't create that fixed expense."
            return nil
        }
    }
}
