import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddPaymentMethodViewModel")
@MainActor
struct AddPaymentMethodViewModelTests {
    private func makeViewModel() -> AddPaymentMethodViewModel {
        AddPaymentMethodViewModel(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    @Test("submit requires a non-blank name and a selected owner")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Chase Visa"
        #expect(!viewModel.canSubmit)

        viewModel.personID = 3
        #expect(viewModel.canSubmit)
    }

    @Test("a blank name after whitespace trimming keeps submit disabled")
    func rejectsBlankName() {
        let viewModel = makeViewModel()
        viewModel.name = "   "
        viewModel.personID = 1
        #expect(!viewModel.canSubmit)
    }

    @Test("defaults to a non-unspecified payment type")
    func defaultsToCashType() {
        let viewModel = makeViewModel()
        #expect(viewModel.type == .cash)
    }
}
