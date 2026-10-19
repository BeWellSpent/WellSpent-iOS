import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

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

    private let restClient: WellSpentREST.Client
    private let methodID: String

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(method: Wellspent_V1_PaymentMethod, restClient: WellSpentREST.Client) {
        self.name = method.name
        self.alias = method.alias
        self.color = method.color
        self.methodID = method.id
        self.restClient = restClient
    }

    func submit() async -> Wellspent_V1_PaymentMethod? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAlias = alias.trimmingCharacters(in: .whitespaces)
        let fallback = "Couldn't update that payment method."

        do {
            let output = try await restClient.updatePaymentMethod(.init(
                path: .init(id: methodID),
                body: .json(.init(name: trimmedName, color: color, alias: trimmedAlias))
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                return nil
            }
            return BudgetRESTMapping.paymentMethod(from: body.method)
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return nil
        }
    }
}
