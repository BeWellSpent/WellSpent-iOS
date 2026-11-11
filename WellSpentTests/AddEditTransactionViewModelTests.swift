import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("AddEditTransactionViewModel")
@MainActor
struct AddEditTransactionViewModelTests {
    private func makeViewModel(mode: AddEditTransactionViewModel.Mode = .add, defaultCategoryID: Int32 = 0) -> AddEditTransactionViewModel {
        AddEditTransactionViewModel(
            mode: mode,
            budgetPeriodID: "period-1",
            currencyCode: "USD",
            defaultCategoryID: defaultCategoryID,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
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
        #expect(!viewModel.canSubmit) // spending needs a category

        viewModel.categoryID = 3
        #expect(viewModel.canSubmit)
    }

    @Test("income and transfers don't need a category; spend and refund do")
    func categoryRequiredByFlow() {
        let viewModel = makeViewModel()
        viewModel.name = "Venmo from Alex"
        viewModel.amountText = "24"
        viewModel.paymentMethodID = "pm-1"
        viewModel.isReceived = true
        #expect(viewModel.flow == .refund) // money in starts on the first "in" choice
        #expect(!viewModel.canSubmit)
        viewModel.flow = .transfer
        #expect(viewModel.canSubmit)
        viewModel.flow = .income
        #expect(viewModel.canSubmit)
    }

    @Test("switching direction keeps a flow that still fits and replaces one that doesn't")
    func directionChangeNormalizesFlow() {
        let viewModel = makeViewModel()
        viewModel.flow = .transfer
        viewModel.isReceived = true
        #expect(viewModel.flow == .transfer)
        viewModel.flow = .income
        viewModel.isReceived = false
        #expect(viewModel.flow == .spend)
    }

    @Test("editing reads the transaction's flow")
    func editReadsFlow() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-9"
            $0.name = "Venmo from Alex"
            $0.amount = .with { $0.units = -24; $0.currency = "USD" }
            $0.flow = "transfer"
        }
        let viewModel = AddEditTransactionViewModel(mode: .edit(transaction), budgetPeriodID: "p", currencyCode: "USD", restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"))
        #expect(viewModel.flow == .transfer)
        #expect(viewModel.isReceived)
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
        let viewModel = makeViewModel(mode: .add)
        #expect(!viewModel.isLocked)
    }

    @Test("editing a manual transaction in any period is not locked (#120)")
    func editModeNotLockedForManualRows() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = "pm-1"
        }
        let viewModel = makeViewModel(mode: .edit(transaction))
        #expect(!viewModel.isLocked)
    }

    @Test("editing a Plaid-imported transaction locks it")
    func editModeLockedWhenPlaidImported() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = "pm-1"
            $0.isPlaidImported = true
        }
        let viewModel = makeViewModel(mode: .edit(transaction))
        #expect(viewModel.isLocked)
    }

    @Test("editing an active, non-Plaid transaction is not locked")
    func editModeNotLockedWhenActiveAndManual() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = "pm-1"
        }
        let viewModel = makeViewModel(mode: .edit(transaction))
        #expect(!viewModel.isLocked)
    }

    @Test("add mode starts categoryID at the given default (issue #76)")
    func addModeStartsAtDefaultCategory() {
        let viewModel = makeViewModel(mode: .add, defaultCategoryID: 7)
        #expect(viewModel.categoryID == 7)
    }

    @Test("add mode defaults categoryID to 0 when no default is given")
    func addModeDefaultsCategoryToZeroWhenUnspecified() {
        let viewModel = makeViewModel(mode: .add)
        #expect(viewModel.categoryID == 0)
    }

    @Test("edit mode ignores defaultCategoryID and prefills from the transaction")
    func editModeIgnoresDefaultCategoryID() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.categoryID = 3
            $0.paymentMethodID = "pm-1"
        }
        let viewModel = makeViewModel(mode: .edit(transaction), defaultCategoryID: 7)
        #expect(viewModel.categoryID == 3)
    }

    @Test("a locked transaction can always submit, even with a blank payment method")
    func canSubmitWhenLockedIgnoresOtherFieldValidation() {
        let transaction = Wellspent_V1_Transaction.with {
            $0.id = "tx-1"
            $0.paymentMethodID = ""
            $0.isPlaidImported = true
        }
        let viewModel = makeViewModel(mode: .edit(transaction))
        #expect(viewModel.canSubmit)
    }
}
