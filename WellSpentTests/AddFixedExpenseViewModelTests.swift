import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddFixedExpenseViewModel")
@MainActor
struct AddFixedExpenseViewModelTests {
    private func makeViewModel() -> AddFixedExpenseViewModel {
        AddFixedExpenseViewModel(
            budgetProfileID: "profile-1",
            currencyCode: "USD",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("submit requires a non-blank name, a valid amount, and a selected payment method")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Rent"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "1500"
        #expect(!viewModel.canSubmit)

        viewModel.paymentMethodID = "pm-1"
        #expect(viewModel.canSubmit)
    }

    @Test("defaults to monthly frequency with a 1-month interval")
    func defaultsToMonthly() {
        let viewModel = makeViewModel()
        #expect(viewModel.frequencyUnit == .month)
        #expect(viewModel.intervalMonths == 1)
        #expect(viewModel.intervalWeeks == 1)
    }
}
