import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("EditFixedExpenseViewModel")
@MainActor
struct EditFixedExpenseViewModelTests {
    private func makeExpense() -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = "fe-1"
            $0.budgetProfileID = "profile-1"
            $0.name = "Rent"
            $0.plannedAmount = .with { $0.units = 1500; $0.currency = "USD" }
            $0.categoryID = 3
            $0.paymentMethodID = "pm-1"
            $0.dayOfMonth = 1
            $0.isActive = true
            $0.intervalMonths = 1
            $0.frequencyUnit = .month
        }
    }

    private func makeViewModel(expense: Wellspent_V1_FixedExpense) -> EditFixedExpenseViewModel {
        EditFixedExpenseViewModel(
            expense: expense,
            currencyCode: "USD",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("pre-fills fields from the existing template")
    func prefillsFromExistingExpense() {
        let viewModel = makeViewModel(expense: makeExpense())

        #expect(viewModel.name == "Rent")
        #expect(viewModel.amountText == "1500")
        #expect(viewModel.categoryID == 3)
        #expect(viewModel.paymentMethodID == "pm-1")
        #expect(viewModel.frequencyUnit == .month)
        #expect(viewModel.intervalMonths == 1)
    }

    @Test("pre-fills a weekly template's interval, not months")
    func prefillsWeeklyExpense() {
        let expense = Wellspent_V1_FixedExpense.with {
            $0.id = "fe-2"
            $0.name = "Groceries"
            $0.plannedAmount = .with { $0.units = 100; $0.currency = "USD" }
            $0.paymentMethodID = "pm-1"
            $0.frequencyUnit = .week
            $0.intervalWeeks = 2
            $0.dayOfWeek = 3
        }
        let viewModel = makeViewModel(expense: expense)

        #expect(viewModel.frequencyUnit == .week)
        #expect(viewModel.intervalWeeks == 2)
    }

    @Test("submit is disabled until a non-blank name and payment method are present")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel(expense: makeExpense())
        #expect(viewModel.canSubmit)

        viewModel.paymentMethodID = ""
        #expect(!viewModel.canSubmit)
    }
}
