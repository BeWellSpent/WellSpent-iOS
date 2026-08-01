import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("BudgetSetupViewModel")
@MainActor
struct BudgetSetupViewModelTests {
    private func makeViewModel() -> BudgetSetupViewModel {
        BudgetSetupViewModel(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    @Test("starts on the create step")
    func startsOnCreateStep() {
        #expect(makeViewModel().step == .create)
    }

    @Test("advance() moves through steps in order and stops at the last one")
    func advanceMovesThroughStepsInOrder() {
        let viewModel = makeViewModel()

        viewModel.advance()
        #expect(viewModel.step == .people)

        viewModel.advance()
        #expect(viewModel.step == .income)

        viewModel.advance()
        #expect(viewModel.step == .paymentMethods)

        viewModel.advance()
        #expect(viewModel.step == .paymentMethods)
    }

    @Test("addPerson with a blank or whitespace-only name is a no-op")
    func addPersonIgnoresBlankName() async {
        let viewModel = makeViewModel()

        await viewModel.addPerson(name: "")
        #expect(viewModel.people.isEmpty)

        await viewModel.addPerson(name: "   ")
        #expect(viewModel.people.isEmpty)
    }
}
