import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("EditPaymentMethodViewModel")
@MainActor
struct EditPaymentMethodViewModelTests {
    @Test("pre-fills name/alias/color from the existing method, with no type field to prefill")
    func prefillsFromExistingMethod() {
        let method = Wellspent_V1_PaymentMethod.with {
            $0.id = "pm-1"
            $0.name = "Chase Visa"
            $0.type = .credit
            $0.budgetPersonID = 4
            $0.color = "#5C6BC0"
            $0.alias = "Household Card"
        }
        let viewModel = EditPaymentMethodViewModel(method: method, authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))

        #expect(viewModel.name == "Chase Visa")
        #expect(viewModel.alias == "Household Card")
        #expect(viewModel.color == "#5C6BC0")
    }

    @Test("submit is disabled until a non-blank name is present")
    func canSubmitReflectsName() {
        let method = Wellspent_V1_PaymentMethod.with {
            $0.id = "pm-1"
            $0.name = "Chase Visa"
        }
        let viewModel = EditPaymentMethodViewModel(method: method, authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
        #expect(viewModel.canSubmit)

        viewModel.name = "   "
        #expect(!viewModel.canSubmit)
    }
}
