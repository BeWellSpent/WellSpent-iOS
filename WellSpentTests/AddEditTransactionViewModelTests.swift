import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddEditTransactionViewModel")
@MainActor
struct AddEditTransactionViewModelTests {
    private func makeViewModel(mode: AddEditTransactionViewModel.Mode = .add, isArchivedPeriod: Bool = false) -> AddEditTransactionViewModel {
        AddEditTransactionViewModel(
            mode: mode,
            budgetPeriodID: "period-1",
            currencyCode: "USD",
            isArchivedPeriod: isArchivedPeriod,
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

    @Test("add mode is never locked")
    func addModeNeverLocked() {
        let viewModel = makeViewModel(mode: .add, isArchivedPeriod: true)
        #expect(!viewModel.isLocked)
    }

    @Test("editing in an archived period locks the transaction")
    func editModeLockedWhenArchived() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = "pm-1"
        }
        let viewModel = makeViewModel(mode: .edit(transaction), isArchivedPeriod: true)
        #expect(viewModel.isLocked)
    }

    @Test("editing a Plaid-imported transaction locks it regardless of archive state")
    func editModeLockedWhenPlaidImported() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = "pm-1"
            $0.isPlaidImported = true
        }
        let viewModel = makeViewModel(mode: .edit(transaction), isArchivedPeriod: false)
        #expect(viewModel.isLocked)
    }

    @Test("editing an active, non-Plaid transaction is not locked")
    func editModeNotLockedWhenActiveAndManual() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = "pm-1"
        }
        let viewModel = makeViewModel(mode: .edit(transaction), isArchivedPeriod: false)
        #expect(!viewModel.isLocked)
    }

    @Test("a locked transaction can always submit, even with a blank payment method")
    func canSubmitWhenLockedIgnoresOtherFieldValidation() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = ""
        }
        let viewModel = makeViewModel(mode: .edit(transaction), isArchivedPeriod: true)
        #expect(viewModel.canSubmit)
    }
}
