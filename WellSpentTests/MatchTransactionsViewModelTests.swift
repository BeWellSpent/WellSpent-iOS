import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("MatchTransactionsViewModel")
@MainActor
struct MatchTransactionsViewModelTests {
    private func makeViewModel() -> MatchTransactionsViewModel {
        MatchTransactionsViewModel(budgetPeriodID: "period-1", budgetProfileID: "profile-1", authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    private func tx(id: String, units: Int64, nanos: Int32 = 0) -> Wellspent_V1_Transaction {
        .with { $0.id = id; $0.amount = .with { $0.units = units; $0.nanos = nanos } }
    }

    private func fixedTx(units: Int64, nanos: Int32 = 0) -> Wellspent_V1_Transaction {
        .with { $0.plannedAmount = .with { $0.units = units; $0.nanos = nanos } }
    }

    @Test("matchesExactly is false with nothing selected")
    func falseWhenNothingSelected() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(variableTransactions: [tx(id: "a", units: 100)], selectedIDs: [])
        #expect(!viewModel.matchesExactly(fixedTx(units: 100)))
    }

    @Test("matchesExactly is false when the total is short")
    func falseWhenShort() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(variableTransactions: [tx(id: "a", units: 80)], selectedIDs: ["a"])
        #expect(!viewModel.matchesExactly(fixedTx(units: 100)))
    }

    @Test("matchesExactly is true when several transactions sum exactly")
    func trueWhenSumMatches() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            variableTransactions: [
                tx(id: "a", units: 166, nanos: 670_000_000),
                tx(id: "b", units: 166, nanos: 670_000_000),
                tx(id: "c", units: 166, nanos: 660_000_000),
            ],
            selectedIDs: ["a", "b", "c"]
        )
        #expect(viewModel.matchesExactly(fixedTx(units: 500)))
    }

    @Test("matchesExactly is false when the total overshoots")
    func falseWhenOver() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(variableTransactions: [tx(id: "a", units: 120)], selectedIDs: ["a"])
        #expect(!viewModel.matchesExactly(fixedTx(units: 100)))
    }
}
