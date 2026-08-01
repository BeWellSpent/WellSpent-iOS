import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class AddEditTransactionViewModel {
    enum Mode {
        case add
        case edit(Wellspent_V1_Transaction)
    }

    var name: String
    var amountText: String
    var isReceived: Bool
    var categoryID: Int32
    var paymentMethodID: String
    var recurring: Bool
    var date: Date

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let mode: Mode

    private let budgetPeriodID: String
    private let currencyCode: String
    private let client: Wellspent_V1_BudgetServiceClient

    /// `transaction_frequency` lookup table seed order (see
    /// WellSpent-backend/internal/db/migrations/000001_init_schema.sql):
    /// One-off = 1, Monthly = 4. Raw int32 on the wire, no proto enum.
    private var transactionFrequencyID: Int32 {
        recurring ? 4 : 1
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
            && !isSubmitting
    }

    init(mode: Mode, budgetPeriodID: String, currencyCode: String, authenticatedClient: ProtocolClient) {
        self.mode = mode
        self.budgetPeriodID = budgetPeriodID
        self.currencyCode = currencyCode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)

        switch mode {
        case .add:
            name = ""
            amountText = ""
            isReceived = false
            categoryID = 0
            paymentMethodID = ""
            recurring = false
            date = Date()
        case .edit(let transaction):
            name = transaction.name
            isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
            amountText = MoneyInput.formatForEditing(units: abs(transaction.amount.units), nanos: abs(transaction.amount.nanos))
            categoryID = transaction.categoryID
            paymentMethodID = transaction.paymentMethodID
            recurring = transaction.transactionFrequencyID != 1
            date = transaction.date.dateOnly
        }
    }

    func submit() async -> Wellspent_V1_Transaction? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let money = Wellspent_V1_Money.with {
            $0.units = isReceived ? -amount.units : amount.units
            $0.nanos = isReceived ? -amount.nanos : amount.nanos
            $0.currency = currencyCode
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let timestamp = Google_Protobuf_Timestamp(dateOnly: date)

        switch mode {
        case .add:
            let request = Wellspent_V1_CreateTransactionRequest.with {
                $0.name = trimmedName
                $0.amount = money
                $0.plannedAmount = money
                $0.date = timestamp
                $0.recurring = recurring
                $0.budgetPeriodID = budgetPeriodID
                $0.categoryID = categoryID
                $0.paymentMethodID = paymentMethodID
                $0.transactionFrequencyID = transactionFrequencyID
                $0.transactionTypeID = TransactionsViewModel.variableTypeID
            }
            let response = await client.createTransaction(request: request)
            switch response.result {
            case .success(let message):
                return message.transaction
            case .failure(let error):
                errorMessage = error.message ?? "Couldn't add that transaction."
                return nil
            }
        case .edit(let existing):
            let request = Wellspent_V1_UpdateTransactionRequest.with {
                $0.id = existing.id
                $0.name = trimmedName
                $0.amount = money
                $0.plannedAmount = money
                $0.date = timestamp
                $0.recurring = recurring
                $0.categoryID = categoryID
                $0.paymentMethodID = paymentMethodID
                $0.transactionFrequencyID = transactionFrequencyID
                $0.transactionTypeID = TransactionsViewModel.variableTypeID
            }
            let response = await client.updateTransaction(request: request)
            switch response.result {
            case .success(let message):
                return message.transaction
            case .failure(let error):
                errorMessage = error.message ?? "Couldn't update that transaction."
                return nil
            }
        }
    }
}
