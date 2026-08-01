import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddSavingsSourceViewModel")
@MainActor
struct AddSavingsSourceViewModelTests {
    private func makeViewModel() -> AddSavingsSourceViewModel {
        AddSavingsSourceViewModel(
            budgetProfileID: "profile-1",
            currencyCode: "USD",
            periodStartDate: nil,
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("submit is disabled until name, amount, payment method, and a valid day count are all present")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Emergency Fund"
        viewModel.amountText = "200"
        #expect(!viewModel.canSubmit) // no payment method, no days yet

        viewModel.paymentMethodID = "pm-1"
        #expect(!viewModel.canSubmit) // still no payment days

        viewModel.paymentDays = [5]
        #expect(viewModel.canSubmit)
    }

    @Test("only 1, 2, or 4 selected days are valid day counts", arguments: [
        (days: [5], valid: true),
        (days: [5, 20], valid: true),
        (days: [1, 8, 15, 22], valid: true),
        (days: [], valid: false),
        (days: [1, 15, 28], valid: false),
    ])
    func onlyValidDayCountsAllowSubmit(_ scenario: (days: [Int], valid: Bool)) {
        let viewModel = makeViewModel()
        viewModel.name = "Emergency Fund"
        viewModel.amountText = "200"
        viewModel.paymentMethodID = "pm-1"
        viewModel.paymentDays = scenario.days

        #expect(viewModel.canSubmit == scenario.valid)
    }

    @Test("daysInMonth is derived from the period start date")
    func daysInMonthReflectsPeriodStartDate() {
        let components = DateComponents(year: 2026, month: 2, day: 1)
        let date = Calendar.current.date(from: components)!
        let viewModel = AddSavingsSourceViewModel(
            budgetProfileID: "profile-1",
            currencyCode: "USD",
            periodStartDate: date,
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
        #expect(viewModel.daysInMonth == 28)
    }
}
