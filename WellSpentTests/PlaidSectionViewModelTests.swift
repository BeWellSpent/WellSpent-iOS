import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PlaidSectionViewModel")
@MainActor
struct PlaidSectionViewModelTests {
    private func makeViewModel() -> PlaidSectionViewModel {
        PlaidSectionViewModel(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    @Test("budgetName(for:) finds the matching budget's name")
    func budgetNameFindsMatch() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(budgets: [
            .with { $0.id = "budget-1"; $0.name = "Household Budget" },
            .with { $0.id = "budget-2"; $0.name = "Side Business" },
        ])

        #expect(viewModel.budgetName(for: "budget-2") == "Side Business")
    }

    @Test("budgetName(for:) falls back to a placeholder when no budget matches")
    func budgetNameFallsBackWhenNoMatch() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(budgets: [.with { $0.id = "budget-1"; $0.name = "Household Budget" }])

        #expect(viewModel.budgetName(for: "nonexistent") == "Unknown budget")
    }

    @Test("handleLinkExit clears the active session state")
    func handleLinkExitClearsState() async {
        let viewModel = makeViewModel()
        await viewModel.startConnect(budgetProfileID: "budget-1") // will fail against the unreachable client, that's fine
        viewModel.handleLinkExit()

        #expect(viewModel.activeLinkToken == nil)
        #expect(viewModel.managingAccountsConnectionID == nil)
    }

    @Test("handleLinkSuccess with no active session is a safe no-op")
    func handleLinkSuccessNoOpWithoutSession() async {
        let viewModel = makeViewModel()
        await viewModel.handleLinkSuccess(publicToken: "public-token-sandbox")

        #expect(viewModel.activeLinkToken == nil)
        #expect(viewModel.managingAccountsConnectionID == nil)
    }
}
