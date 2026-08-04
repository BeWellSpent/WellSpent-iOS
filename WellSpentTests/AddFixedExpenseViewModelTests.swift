import Testing
import Foundation
import WellSpentAPI
@testable import WellSpent

@Suite("AddFixedExpenseViewModel")
@MainActor
struct AddFixedExpenseViewModelTests {
    private func makeViewModel() -> AddFixedExpenseViewModel {
        AddFixedExpenseViewModel(
            budgetProfileID: "profile-1",
            currencyCode: "USD",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("submit requires a non-blank name, a valid amount, and a selected payment method")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Rent"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "1500"
        #expect(!viewModel.canSubmit)

        viewModel.paymentMethodID = "pm-1"
        #expect(viewModel.canSubmit)
    }

    @Test("defaults to monthly frequency with a 1-month interval")
    func defaultsToMonthly() {
        let viewModel = makeViewModel()
        #expect(viewModel.frequencyUnit == .month)
        #expect(viewModel.intervalMonths == 1)
        #expect(viewModel.intervalWeeks == 1)
    }

    @Test("no payment plan by default")
    func noPaymentPlanByDefault() {
        let viewModel = makeViewModel()
        #expect(viewModel.paymentsText.isEmpty)
        #expect(viewModel.endDate == nil)
    }

    @Test("entering a payment count derives an end date")
    func paymentsTextDerivesEndDate() {
        let viewModel = makeViewModel()
        viewModel.setStartDate(Date(timeIntervalSince1970: 1_767_225_600)) // 2026-01-01
        viewModel.handlePaymentsTextChange("6")
        #expect(viewModel.endDate != nil)
        #expect(viewModel.paymentsText == "6")
    }

    @Test("picking an end date derives a payment count")
    func endDateDerivesPaymentsText() {
        let viewModel = makeViewModel()
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01
        viewModel.setStartDate(start)
        let sixMonthsLater = Calendar.current.date(byAdding: .month, value: 5, to: start)!
        viewModel.handleEndDateChange(sixMonthsLater)
        #expect(viewModel.paymentsText == "6")
    }

    @Test("clearing the payment count clears the end date")
    func clearingPaymentsTextClearsEndDate() {
        let viewModel = makeViewModel()
        viewModel.handlePaymentsTextChange("6")
        #expect(viewModel.endDate != nil)
        viewModel.handlePaymentsTextChange("")
        #expect(viewModel.endDate == nil)
    }

    @Test("clearing the end date clears the payment count")
    func clearingEndDateClearsPaymentsText() {
        let viewModel = makeViewModel()
        viewModel.handlePaymentsTextChange("6")
        viewModel.handleEndDateChange(nil)
        #expect(viewModel.paymentsText.isEmpty)
    }

    @Test("changing the start date recalculates the end date when a payment count is set")
    func startDateChangeRecalculatesEndDate() {
        let viewModel = makeViewModel()
        viewModel.handlePaymentsTextChange("6")
        let originalEndDate = viewModel.endDate
        viewModel.setStartDate(Calendar.current.date(byAdding: .month, value: 1, to: viewModel.startDate)!)
        #expect(viewModel.endDate != originalEndDate)
        #expect(viewModel.paymentsText == "6")
    }
}
