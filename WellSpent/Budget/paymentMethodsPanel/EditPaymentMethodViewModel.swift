import Foundation
import Observation
import WellSpentAPI

/// Kept separate from `AddPaymentMethodViewModel` — payment type is
/// immutable after creation (see docs/features/transactions.md), so the
/// edit form has no type field at all, only name/alias/color.
@MainActor
@Observable
final class EditPaymentMethodViewModel {
    var name: String
    var alias: String
    var color: String

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient
    private let methodID: String

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(method: Wellspent_V1_PaymentMethod, authenticatedClient: ProtocolClient) {
        self.name = method.name
        self.alias = method.alias
        self.color = method.color
        self.methodID = method.id
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func submit() async -> Wellspent_V1_PaymentMethod? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_UpdatePaymentMethodRequest.with {
            $0.id = methodID
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.color = color
            $0.alias = alias.trimmingCharacters(in: .whitespaces)
        }
        let response = await client.updatePaymentMethod(request: request)

        switch response.result {
        case .success(let message):
            return message.method
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that payment method."
            return nil
        }
    }
}
