import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("SavingsViewModel")
@MainActor
struct SavingsViewModelTests {
    private func makeViewModel(currentUserID: String? = nil) -> SavingsViewModel {
        SavingsViewModel(
            budgetProfileID: "profile-1",
            currencyCode: "USD",
            localeIdentifier: "en",
            currentUserID: currentUserID,
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func source(id: Int64, budgetPersonID: Int64 = 0) -> Wellspent_V1_SavingsSource {
        .with { $0.id = id; $0.name = "Source \(id)"; $0.budgetPersonID = budgetPersonID }
    }

    private func person(id: Int64, userID: String, focusedView: Bool) -> Wellspent_V1_BudgetPerson {
        .with { $0.id = id; $0.userID = userID; $0.focusedViewEnabled = focusedView }
    }

    @Test("visibleSources includes everyone when Focused View is off")
    func visibleSourcesIncludesEveryoneWhenOff() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            sources: [source(id: 1, budgetPersonID: 1), source(id: 2, budgetPersonID: 2)],
            people: [person(id: 1, userID: "me", focusedView: false)]
        )
        #expect(viewModel.visibleSources.map(\.id) == [1, 2])
    }

    @Test("visibleSources scopes to mine plus unattributed when Focused View is on")
    func visibleSourcesScopesWhenOn() {
        let viewModel = makeViewModel(currentUserID: "me")
        viewModel.setStateForTesting(
            sources: [source(id: 1, budgetPersonID: 1), source(id: 2, budgetPersonID: 2), source(id: 3, budgetPersonID: 0)],
            people: [person(id: 1, userID: "me", focusedView: true)]
        )
        #expect(viewModel.visibleSources.map(\.id) == [1, 3])
    }
}
