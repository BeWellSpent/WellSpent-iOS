import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AddPaymentMethodViewModel {
    var name = ""
    var type: Wellspent_V1_PaymentType = .cash
    var personID: Int64 = 0
    var color = ""

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let restClient: WellSpentREST.Client

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && personID != 0 && !isSubmitting
    }

    init(restClient: WellSpentREST.Client) {
        self.restClient = restClient
    }

    func submit() async -> Wellspent_V1_PaymentMethod? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let fallback = "Couldn't create that payment method."

        do {
            let output = try await restClient.createPaymentMethod(.init(body: .json(.init(
                name: trimmedName,
                _type: BudgetRESTMapping.restPaymentType(from: type),
                budgetPersonId: personID,
                color: color
            ))))
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
