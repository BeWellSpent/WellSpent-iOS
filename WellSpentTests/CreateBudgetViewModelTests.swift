import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("CreateBudgetViewModel")
@MainActor
struct CreateBudgetViewModelTests {
    private func makeViewModel() -> CreateBudgetViewModel {
        CreateBudgetViewModel(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
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

    @Test("passes a message-bearing error through unchanged")
    func mapsErrorWithMessage() {
        let message = CreateBudgetViewModel.errorMessage(for: ConnectError(code: .invalidArgument, message: "name too long"))
        #expect(message == "name too long")
    }

    @Test("falls back to a generic message when the error has none")
    func mapsErrorWithoutMessage() {
        let message = CreateBudgetViewModel.errorMessage(for: ConnectError(code: .internalError, message: nil))
        #expect(message == "Couldn't create that budget.")
    }
}
