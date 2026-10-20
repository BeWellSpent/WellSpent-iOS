import Foundation
import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

/// Covers the local state each delete path leaves behind. The RPC itself is
/// an unreachable client (`http://localhost:1`, the convention here), so
/// these exercise the seeding/removal logic rather than the network call.
@MainActor
@Suite("FixedExpensesViewModel")
struct FixedExpensesViewModelTests {
    private func makeViewModel(currentUserID: String? = nil) -> FixedExpensesViewModel {
        FixedExpensesViewModel(
            budgetPeriodID: "period-1",
            budgetProfileID: "budget-1",
            currencyCode: "USD",
            localeIdentifier: "en",
            currentUserID: currentUserID,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func expense(id: String, paymentMethodID: String = "") -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = id
            $0.name = "Rent"
            $0.isActive = true
            $0.paymentMethodID = paymentMethodID
        }
    }

    @Test("an upcoming template is one of the templates the Future section reads")
    func upcomingTemplateIsVisibleBeforeDelete() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(fixedExpenses: [expense(id: "fe-1"), expense(id: "fe-2")])

        // No spawned transactions, so both templates are upcoming — the state
        // in which the Future row's delete is reachable at all.
        let upcoming = UpcomingFixedExpenses.notDue(
            expenses: viewModel.fixedExpenses,
            transactions: viewModel.transactions
        )
        #expect(upcoming.map(\.id) == ["fe-1", "fe-2"])
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

    @Test("deleting a transaction's template is a no-op when it has none")
    func deleteWithoutTemplateIsNoOp() async {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            fixedExpenses: [expense(id: "fe-1")],
            transactions: [.with { $0.id = "tx-1" }]
        )

        // fixedExpenseID is empty, so `delete` returns before any request —
        // nothing is removed and no error is surfaced.
        await viewModel.delete(.with { $0.id = "tx-1" })

        #expect(viewModel.fixedExpenses.map(\.id) == ["fe-1"])
        #expect(viewModel.transactions.map(\.id) == ["tx-1"])
        #expect(viewModel.errorMessage == nil)
    }

    // issue #77: the Future section must only show the caller's own (or
    // unattributed) upcoming bills when Focused View is on.
    @Test("focused view hides another person's template, keeps unattributed, and keeps fixedExpenses unfiltered")
    func visibleFixedExpensesScopesUnderFocusedView() {
        let viewModel = makeViewModel(currentUserID: "me")
        let methods: [Wellspent_V1_PaymentMethod] = [
            .with { $0.id = "pm-mine"; $0.budgetPersonID = 1 },
            .with { $0.id = "pm-other"; $0.budgetPersonID = 2 }
        ]
        let people: [Wellspent_V1_BudgetPerson] = [.with { $0.id = 1; $0.userID = "me" }]
        viewModel.setStateForTesting(
            fixedExpenses: [
                expense(id: "mine", paymentMethodID: "pm-mine"),
                expense(id: "other", paymentMethodID: "pm-other"),
                expense(id: "unattributed", paymentMethodID: "")
            ],
            people: people,
            paymentMethods: methods,
            isFocusedView: true
        )

        #expect(Set(viewModel.visibleFixedExpenses.map(\.id)) == ["mine", "unattributed"])
        #expect(Set(viewModel.fixedExpenses.map(\.id)) == ["mine", "other", "unattributed"])
    }

    @Test("focused view off returns every template unfiltered")
    func visibleFixedExpensesUnfilteredWhenNotFocused() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            fixedExpenses: [expense(id: "mine", paymentMethodID: "pm-mine"), expense(id: "other", paymentMethodID: "pm-other")],
            isFocusedView: false
        )

        #expect(Set(viewModel.visibleFixedExpenses.map(\.id)) == ["mine", "other"])
    }
}
