import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("IncomeViewModel")
@MainActor
struct IncomeViewModelTests {
    private func makeViewModel() -> IncomeViewModel {
        IncomeViewModel(budgetProfileID: "profile-1", authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    private func source(id: Int64) -> Wellspent_V1_IncomeSource {
        .with { $0.id = id; $0.name = "Source \(id)" }
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
}
