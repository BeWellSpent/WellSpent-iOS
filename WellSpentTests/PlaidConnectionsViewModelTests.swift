import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PlaidConnectionsViewModel")
@MainActor
struct PlaidConnectionsViewModelTests {
    private func makeViewModel() -> PlaidConnectionsViewModel {
        PlaidConnectionsViewModel(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
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

@Suite("PlaidConnectionsViewModel — budget scope")
@MainActor
struct PlaidConnectionsViewModelBudgetScopeTests {
    private func makeViewModel(budgetProfileID: String?) -> PlaidConnectionsViewModel {
        PlaidConnectionsViewModel(
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            budgetProfileID: budgetProfileID
        )
    }

    @Test("A budget-scoped list captions rows with who linked the connection")
    func budgetScopeSubtitleIsOwner() {
        let viewModel = makeViewModel(budgetProfileID: "budget-1")
        let connection = Wellspent_V1_PlaidConnection.with {
            $0.budgetProfileID = "budget-1"
            $0.ownerName = "Grace Hopper"
        }

        #expect(viewModel.subtitle(for: connection) == "Grace Hopper")
    }

    @Test("A cross-budget list captions rows with the budget they feed")
    func userScopeSubtitleIsBudget() {
        let viewModel = makeViewModel(budgetProfileID: nil)
        viewModel.setStateForTesting(budgets: [
            .with { $0.id = "budget-1"; $0.name = "Household Budget" },
        ])
        let connection = Wellspent_V1_PlaidConnection.with {
            $0.budgetProfileID = "budget-1"
            $0.ownerName = "Grace Hopper"
        }

        #expect(viewModel.subtitle(for: connection) == "Household Budget")
    }

    @Test("A budget-scoped screen hides warnings belonging to other budgets")
    func warningsFilteredToBudget() {
        let viewModel = makeViewModel(budgetProfileID: "budget-1")
        viewModel.setStateForTesting(warnings: [
            .with { $0.budgetProfileID = "budget-1"; $0.memberName = "Ada" },
            .with { $0.budgetProfileID = "budget-2"; $0.memberName = "Grace" },
        ])

        #expect(viewModel.visibleWarnings.count == 1)
        #expect(viewModel.visibleWarnings.first?.memberName == "Ada")
    }

    @Test("A cross-budget screen shows every warning")
    func warningsUnfilteredWithoutScope() {
        let viewModel = makeViewModel(budgetProfileID: nil)
        viewModel.setStateForTesting(warnings: [
            .with { $0.budgetProfileID = "budget-1" },
            .with { $0.budgetProfileID = "budget-2" },
        ])

        #expect(viewModel.visibleWarnings.count == 2)
    }
}
