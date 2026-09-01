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
        #expect(viewModel.step == .paymentMethods)

        viewModel.advance()
        #expect(viewModel.step == .income)

        viewModel.advance()
        #expect(viewModel.step == .savings)

        viewModel.advance()
        #expect(viewModel.step == .savings)
    }

    // Savings spends from a payment method, so that step has to come first.
    // This is the reason the order changed; assert the constraint rather than
    // trusting the enum to stay put. Mirrors web's `setupFlow/steps.test.ts`.
    @Test("payment methods precede both income and savings")
    func paymentMethodsComeBeforeWhatNeedsThem() {
        let order = BudgetSetupViewModel.Step.allCases
        let paymentMethods = order.firstIndex(of: .paymentMethods)!
        #expect(paymentMethods < order.firstIndex(of: .savings)!)
        #expect(paymentMethods < order.firstIndex(of: .income)!)
    }

    @Test("every step names itself, so the sheet title is never blank")
    func everyStepHasATitle() {
        for step in BudgetSetupViewModel.Step.allCases {
            #expect(!step.title.isEmpty)
        }
    }

    @Test("addPerson with a blank or whitespace-only name is a no-op")
    func addPersonIgnoresBlankName() async {
        let viewModel = makeViewModel()

        await viewModel.addPerson(name: "", email: "", role: .collaborator)
        #expect(viewModel.people.isEmpty)

        await viewModel.addPerson(name: "   ", email: "", role: .collaborator)
        #expect(viewModel.people.isEmpty)
    }

    // Nothing has been created yet on the first step, so there is nothing to
    // delete — cancelling must still report success and let the sheet close.
    @Test("cancelling before the budget exists succeeds with nothing to delete")
    func cancelBeforeCreationSucceeds() async {
        let viewModel = makeViewModel()
        let didCancel = await viewModel.cancel()
        #expect(didCancel)
        #expect(viewModel.profile == nil)
    }
}
