import Testing
import Foundation
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

/// The RPC itself is an unreachable client (`http://localhost:1`, the
/// convention here — see `FixedExpenseTemplatesViewModelTests`), so the
/// submit path below exercises the failure branch; a real success
/// round-trip needs a live server and isn't covered by this repo's
/// no-network-mocking tests.
@MainActor
@Suite("PayFixedExpenseInFullViewModel")
struct PayFixedExpenseInFullViewModelTests {
    private func makeViewModel(remainingBalance: Wellspent_V1_Money = .with { $0.units = 450; $0.nanos = 0; $0.currency = "USD" }) -> PayFixedExpenseInFullViewModel {
        PayFixedExpenseInFullViewModel(
            budgetProfileID: "budget-1",
            fixedExpenseID: "fe-1",
            currencyCode: "USD",
            remainingBalance: remainingBalance,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("prefills the amount field from the remaining balance")
    func prefillsFromRemainingBalance() {
        let viewModel = makeViewModel(remainingBalance: .with { $0.units = 450; $0.nanos = 500_000_000; $0.currency = "USD" })
        #expect(viewModel.amountText == "450.50")
    }

    @Test("prefills zero when there is no remaining balance loaded yet")
    func prefillsZeroWhenNoBalance() {
        let viewModel = makeViewModel(remainingBalance: Wellspent_V1_Money())
        #expect(viewModel.amountText == "0")
    }

    @Test("canSubmit requires a valid amount")
    func canSubmitReflectsAmount() {
        let viewModel = makeViewModel()
        #expect(viewModel.canSubmit)

        viewModel.amountText = "not a number"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "100"
        #expect(viewModel.canSubmit)
    }

    @Test("defaults the paid date to today")
    func defaultsPaidDateToToday() {
        let viewModel = makeViewModel()
        #expect(Calendar.current.isDateInToday(viewModel.paidDate))
    }

    @Test("a failed submit surfaces an error message and returns nil")
    func failedSubmitSurfacesError() async {
        let viewModel = makeViewModel()

        let result = await viewModel.submit()

        #expect(result == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.isSubmitting)
    }
}
