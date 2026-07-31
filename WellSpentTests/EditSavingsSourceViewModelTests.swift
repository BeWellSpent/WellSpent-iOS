import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("EditSavingsSourceViewModel")
@MainActor
struct EditSavingsSourceViewModelTests {
    private func makeSource() -> Wellspent_V1_SavingsSource {
        .with {
            $0.id = 42
            $0.budgetProfileID = "profile-1"
            $0.name = "Emergency Fund"
            $0.amount = .with { $0.units = 300; $0.currency = "USD" }
            $0.paymentMethodID = "pm-1"
            $0.paymentDays = [5, 20]
        }
    }

    private func makeViewModel(source: Wellspent_V1_SavingsSource) -> EditSavingsSourceViewModel {
        EditSavingsSourceViewModel(
            source: source,
            currencyCode: "USD",
            periodStartDate: nil,
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("pre-fills fields from the existing source")
    func prefillsFromExistingSource() {
        let viewModel = makeViewModel(source: makeSource())

        #expect(viewModel.name == "Emergency Fund")
        #expect(viewModel.amountText == "300")
        #expect(viewModel.paymentMethodID == "pm-1")
        #expect(viewModel.paymentDays == [5, 20])
    }

    @Test("submit is disabled until name and amount are valid; payment method is optional")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel(source: makeSource())
        #expect(viewModel.canSubmit)

        viewModel.paymentMethodID = ""
        #expect(viewModel.canSubmit) // payment method optional on edit

        viewModel.name = ""
        #expect(!viewModel.canSubmit)
    }

    @Test("zero payment days is a valid day count on edit, unlike add")
    func zeroPaymentDaysIsValidOnEdit() {
        let viewModel = makeViewModel(source: makeSource())
        viewModel.paymentDays = []
        #expect(viewModel.canSubmit)
    }

    @Test("an invalid day count (e.g. 3) disables submit")
    func invalidDayCountDisablesSubmit() {
        let viewModel = makeViewModel(source: makeSource())
        viewModel.paymentDays = [1, 10, 20]
        #expect(!viewModel.canSubmit)
    }
}
