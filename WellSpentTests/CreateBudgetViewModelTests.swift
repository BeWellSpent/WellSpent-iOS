import Testing
import WellSpentREST
@testable import WellSpent

@Suite("CreateBudgetViewModel")
@MainActor
struct CreateBudgetViewModelTests {
    private func makeViewModel() -> CreateBudgetViewModel {
        CreateBudgetViewModel(
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("submit is disabled until a non-blank name is present")
    func canSubmitReflectsName() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "   "
        #expect(!viewModel.canSubmit)

        viewModel.name = "Household Budget"
        #expect(viewModel.canSubmit)
    }
}
