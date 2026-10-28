import Foundation
import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

/// Covers the local state each mutation leaves behind. The RPC itself is an
/// unreachable client (`http://localhost:1`, the convention here), so these
/// exercise the seeding/mutation logic rather than the network call.
@MainActor
@Suite("FixedExpenseTemplatesViewModel")
struct FixedExpenseTemplatesViewModelTests {
    private func makeViewModel() -> FixedExpenseTemplatesViewModel {
        FixedExpenseTemplatesViewModel(
            budgetProfileID: "budget-1",
            currencyCode: "USD",
            localeIdentifier: "en",
            currentUserID: nil,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func expense(id: String, name: String = "Rent") -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = id
            $0.name = name
            $0.isActive = true
        }
    }

    @Test("adding a template from create appends it")
    func addTemplateAppends() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(fixedExpenses: [expense(id: "fe-1")])

        viewModel.addTemplate(expense(id: "fe-2", name: "Gym"))

        #expect(viewModel.fixedExpenses.map(\.id) == ["fe-1", "fe-2"])
    }

    @Test("replacing a template updates it in place")
    func replaceTemplateUpdatesInPlace() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(fixedExpenses: [expense(id: "fe-1"), expense(id: "fe-2")])

        viewModel.replaceTemplate(expense(id: "fe-1", name: "Rent (updated)"))

        #expect(viewModel.fixedExpenses.first(where: { $0.id == "fe-1" })?.name == "Rent (updated)")
        #expect(viewModel.fixedExpenses.map(\.id) == ["fe-1", "fe-2"])
    }

    @Test("replacing a template with no match is a no-op")
    func replaceTemplateWithoutMatchIsNoOp() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(fixedExpenses: [expense(id: "fe-1")])

        viewModel.replaceTemplate(expense(id: "fe-missing"))

        #expect(viewModel.fixedExpenses.map(\.id) == ["fe-1"])
    }

    @Test("a failed delete leaves the template in place and reports why")
    func failedDeleteKeepsTemplate() async {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(fixedExpenses: [expense(id: "fe-1")])

        // The client can't reach anything, so this is the failure path: the
        // row must not disappear optimistically.
        await viewModel.deleteTemplate(expense(id: "fe-1"))

        #expect(viewModel.fixedExpenses.map(\.id) == ["fe-1"])
        #expect(viewModel.errorMessage != nil)
    }
}
