import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("IncomeViewModel")
@MainActor
struct IncomeViewModelTests {
    private func makeViewModel(currentUserID: String? = nil) -> IncomeViewModel {
        IncomeViewModel(
            budgetProfileID: "profile-1",
            currentUserID: currentUserID,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func source(id: Int64, budgetPersonID: Int64 = 0) -> Wellspent_V1_IncomeSource {
        .with { $0.id = id; $0.name = "Source \(id)"; $0.budgetPersonID = budgetPersonID }
    }

    private func person(id: Int64, userID: String, focusedView: Bool) -> Wellspent_V1_BudgetPerson {
        .with { $0.id = id; $0.userID = userID; $0.focusedViewEnabled = focusedView }
    }

    @Test("isAtLimit is true only for free-tier users with 2+ income sources")
    func isAtLimitReflectsFreeAndCount() {
        let viewModel = makeViewModel()

        viewModel.setStateForTesting(sources: [source(id: 1)], isFree: true)
        #expect(!viewModel.isAtLimit)

        viewModel.setStateForTesting(sources: [source(id: 1), source(id: 2)], isFree: true)
        #expect(viewModel.isAtLimit)
    }

    @Test("Pro/Lifetime users are never at the limit regardless of source count")
    func nonFreeNeverAtLimit() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(sources: [source(id: 1), source(id: 2), source(id: 3)], isFree: false)
        #expect(!viewModel.isAtLimit)
    }

    @Test("visibleSources includes everyone when Focused View is off")
    func visibleSourcesIncludesEveryoneWhenOff() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            sources: [source(id: 1, budgetPersonID: 1), source(id: 2, budgetPersonID: 2)],
            isFree: false,
            people: [person(id: 1, userID: "me", focusedView: false)]
        )
        #expect(viewModel.visibleSources.map(\.id) == [1, 2])
    }

    @Test("visibleSources scopes to mine plus unattributed when Focused View is on")
    func visibleSourcesScopesWhenOn() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            sources: [source(id: 1, budgetPersonID: 1), source(id: 2, budgetPersonID: 2), source(id: 3, budgetPersonID: 0)],
            isFree: false,
            people: [person(id: 1, userID: "me", focusedView: true)]
        )
        #expect(viewModel.visibleSources.map(\.id) == [1, 3])
    }
}
