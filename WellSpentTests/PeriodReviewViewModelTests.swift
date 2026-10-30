import Foundation
import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("PeriodReviewViewModel")
@MainActor
struct PeriodReviewViewModelTests {
    private func period(id: String) -> Wellspent_V1_BudgetPeriod {
        .with { $0.id = id }
    }

    private func makeViewModel(previousPeriod: Wellspent_V1_BudgetPeriod?) -> PeriodReviewViewModel {
        PeriodReviewViewModel(
            period: period(id: "new"),
            previousPeriod: previousPeriod,
            budgetProfileID: "profile-1",
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("load leaves both lists empty, with no network call, when there is no previous period")
    func loadWithNoPreviousPeriodIsEmpty() async {
        let viewModel = makeViewModel(previousPeriod: nil)
        await viewModel.load()
        #expect(viewModel.carriedOverTransactions.isEmpty)
        #expect(viewModel.unpaidFixedTransactions.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("confirm surfaces an error and returns false on a connectivity failure")
    func confirmFailsOnConnectivityError() async {
        let viewModel = makeViewModel(previousPeriod: period(id: "previous"))
        let result = await viewModel.confirm()
        #expect(result == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("retrigger surfaces an error on a connectivity failure, without crashing")
    func retriggerFailsOnConnectivityError() async {
        let viewModel = makeViewModel(previousPeriod: period(id: "previous"))
        await viewModel.retrigger()
        #expect(viewModel.errorMessage != nil)
    }

    @Test("markUnpaidFixedTransactionPaid is a no-op when there is no previous period")
    func markUnpaidFixedTransactionPaidNoOpWithoutPreviousPeriod() async {
        let viewModel = makeViewModel(previousPeriod: nil)
        let transaction = Wellspent_V1_Transaction.with { $0.id = "t1" }
        viewModel.setStateForTesting(unpaidFixedTransactions: [transaction])
        await viewModel.markUnpaidFixedTransactionPaid(transaction, paidAmount: .with { $0.units = 100 }, paidAt: Date())
        #expect(viewModel.unpaidFixedTransactions.map(\.id) == ["t1"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("replaceCarriedOverTransaction mutates the matching row in place")
    func replaceCarriedOverTransactionMutatesInPlace() {
        let viewModel = makeViewModel(previousPeriod: period(id: "previous"))
        let original = Wellspent_V1_Transaction.with { $0.id = "t1"; $0.name = "Original" }
        viewModel.setStateForTesting(carriedOverTransactions: [original])

        let updated = Wellspent_V1_Transaction.with { $0.id = "t1"; $0.name = "Updated" }
        viewModel.replaceCarriedOverTransaction(updated)

        #expect(viewModel.carriedOverTransactions.first?.name == "Updated")
    }

    @Test("replaceCarriedOverTransaction is a no-op for an id that isn't present")
    func replaceCarriedOverTransactionNoOpForUnknownID() {
        let viewModel = makeViewModel(previousPeriod: period(id: "previous"))
        let original = Wellspent_V1_Transaction.with { $0.id = "t1"; $0.name = "Original" }
        viewModel.setStateForTesting(carriedOverTransactions: [original])

        viewModel.replaceCarriedOverTransaction(.with { $0.id = "unknown"; $0.name = "Updated" })

        #expect(viewModel.carriedOverTransactions.map(\.name) == ["Original"])
    }
}
