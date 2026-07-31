import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class AddPaymentMethodViewModel {
    var name = ""
    var type: Wellspent_V1_PaymentType = .cash
    var personID: Int64 = 0
    var color = ""

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && personID != 0 && !isSubmitting
    }

    init(authenticatedClient: ProtocolClient) {
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func submit() async -> Wellspent_V1_PaymentMethod? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_CreatePaymentMethodRequest.with {
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.type = type
            $0.budgetPersonID = personID
            $0.color = color
        }
        let response = await client.createPaymentMethod(request: request)

        switch response.result {
        case .success(let message):
            return message.method
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't create that payment method."
            return nil
        }
    }
}
