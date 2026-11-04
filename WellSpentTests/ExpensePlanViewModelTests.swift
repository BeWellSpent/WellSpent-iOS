import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("ExpensePlanViewModel totals")
@MainActor
struct ExpensePlanViewModelTests {
    private func makeViewModel() -> ExpensePlanViewModel {
        ExpensePlanViewModel(
            budgetPeriodID: "period-1", budgetProfileID: "budget-1", currencyCode: "USD",
            localeIdentifier: "en", currentUserID: nil,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func money(_ units: Int64) -> Wellspent_V1_Money { .with { $0.units = units; $0.currency = "USD" } }

    @Test("committed and remaining are exposed with and without savings")
    func totalsWithAndWithoutSavings() {
        let viewModel = makeViewModel()
        viewModel.setSummaryForTesting(.with {
            $0.incomeFromSources = money(1000)
            $0.totalCommitted = money(400)
            $0.totalCommittedIncludingSavings = money(550)
            $0.remainderPlan = money(600)
        }, remainderPlanIncludingSavings: money(450))

        #expect(viewModel.committedTotal.units == 400)
        #expect(viewModel.committedIncludingSavingsTotal.units == 550)
        #expect(viewModel.remainderTotal.units == 600)
        #expect(viewModel.remainderIncludingSavingsTotal?.units == 450)
    }

    @Test("remaining with savings is absent when the server did not send it")
    func missingRemainderIncludingSavings() {
        let viewModel = makeViewModel()
        viewModel.setSummaryForTesting(.with { $0.remainderPlan = money(600) }, remainderPlanIncludingSavings: nil)

        #expect(viewModel.remainderIncludingSavingsTotal == nil)
    }
}
