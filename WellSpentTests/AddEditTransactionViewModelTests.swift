import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddEditTransactionViewModel")
@MainActor
struct AddEditTransactionViewModelTests {
    private func makeViewModel(mode: AddEditTransactionViewModel.Mode = .add) -> AddEditTransactionViewModel {
        AddEditTransactionViewModel(
            mode: mode,
            budgetPeriodID: "period-1",
            currencyCode: "USD",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("submit requires a non-blank name, a valid amount, and a selected payment method")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Groceries"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "42.50"
        #expect(!viewModel.canSubmit)

        viewModel.paymentMethodID = "pm-1"
        #expect(viewModel.canSubmit)
    }

    @Test("editing an existing Spent transaction pre-fills fields with isReceived false")
    func editModePrefillSpent() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.name = "Groceries"
            $0.amount = .with { $0.units = 50; $0.nanos = 0; $0.currency = "USD" }
            $0.categoryID = 3
            $0.paymentMethodID = "pm-1"
            $0.transactionFrequencyID = 1
        }
        let viewModel = makeViewModel(mode: .edit(transaction))

        #expect(viewModel.name == "Groceries")
        #expect(viewModel.amountText == "50")
        #expect(viewModel.isReceived == false)
        #expect(viewModel.categoryID == 3)
        #expect(viewModel.paymentMethodID == "pm-1")
        #expect(viewModel.recurring == false)
    }

    @Test("editing an existing Received transaction reconstructs isReceived from the negative amount")
    func editModePrefillReceived() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-2"
            $0.name = "Refund"
            $0.amount = .with { $0.units = -20; $0.nanos = 0; $0.currency = "USD" }
            $0.transactionFrequencyID = 4
        }
        let viewModel = makeViewModel(mode: .edit(transaction))

        #expect(viewModel.isReceived == true)
        #expect(viewModel.amountText == "20")
        #expect(viewModel.recurring == true)
    }
}
