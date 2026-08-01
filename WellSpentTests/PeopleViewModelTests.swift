import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PeopleViewModel")
@MainActor
struct PeopleViewModelTests {
    private func makeViewModel() -> PeopleViewModel {
        PeopleViewModel(
            budgetProfileID: "profile-1",
            budgetOwnerUserID: "owner-1",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func person(id: Int64) -> Wellspent_V1_BudgetPerson {
        .with { $0.id = id; $0.userName = "Person \(id)" }
    }

    @Test("isAtLimit is true only for free-tier users with 2+ people")
    func isAtLimitReflectsFreeAndCount() {
        let viewModel = makeViewModel()

        viewModel.setStateForTesting(people: [person(id: 1)], isFree: true)
        #expect(!viewModel.isAtLimit)

        viewModel.setStateForTesting(people: [person(id: 1), person(id: 2)], isFree: true)
        #expect(viewModel.isAtLimit)
    }

    @Test("Pro/Lifetime users are never at the limit regardless of people count")
    func nonFreeNeverAtLimit() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(people: [person(id: 1), person(id: 2), person(id: 3)], isFree: false)
        #expect(!viewModel.isAtLimit)
    }

    @Test("canAddPerson requires a non-blank name and blocks once at the free-tier limit")
    func canAddPersonReflectsNameAndLimit() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canAddPerson)

        viewModel.newPersonName = "Grace"
        #expect(viewModel.canAddPerson)

        viewModel.setStateForTesting(people: [person(id: 1), person(id: 2)], isFree: true)
        #expect(!viewModel.canAddPerson)
    }
}
