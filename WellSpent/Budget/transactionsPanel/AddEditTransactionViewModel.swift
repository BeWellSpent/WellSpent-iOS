import Foundation
import Observation
import os
import WellSpentAPI

@MainActor
@Observable
final class AddEditTransactionViewModel {
    private static let logger = AppLogger.logger("Transactions")

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

    /// True once a transaction's other fields are frozen — either its
    /// period has archived, it's Plaid-imported (`isPlaidImported`), or the
    /// caller passed `forceLocked` (e.g. a Fixed transaction whose template
    /// is missing/deactivated — see `FixedExpensesListView`) — and only its
    /// category can still change. See docs/features/budget-list-view-rework.md.
    /// Never true in `.add` mode.
    let isLocked: Bool

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
        guard !isSubmitting else { return false }
        if isLocked { return true }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
    }

    init(mode: Mode, budgetPeriodID: String, currencyCode: String, isArchivedPeriod: Bool = false, forceLocked: Bool = false, authenticatedClient: ProtocolClient) {
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
            isLocked = false
            Self.logger.info("opened in add mode budgetPeriodID=\(budgetPeriodID, privacy: .public)")
        case .edit(let transaction):
            name = transaction.name
            isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
            amountText = MoneyInput.formatForEditing(units: abs(transaction.amount.units), nanos: abs(transaction.amount.nanos))
            categoryID = transaction.categoryID
            paymentMethodID = transaction.paymentMethodID
            recurring = transaction.transactionFrequencyID != 1
            date = transaction.date.dateOnly
            isLocked = isArchivedPeriod || transaction.isPlaidImported || forceLocked
            Self.logger.info("opened in edit mode transactionID=\(transaction.id, privacy: .public) isArchivedPeriod=\(isArchivedPeriod, privacy: .public) isPlaidImported=\(transaction.isPlaidImported, privacy: .public) forceLocked=\(forceLocked, privacy: .public) isLocked=\(self.isLocked, privacy: .public)")
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

        // Locked (archived period or Plaid-imported): send every field back
        // exactly as originally recorded except category — the backend
        // rejects an update that changes anything else in that case.
        // Reconstructing from (unchanged, disabled) form state risks a
        // spurious mismatch from formatting round-trips, so this reads off
        // the transaction record directly instead — but `existing` (captured
        // when this sheet was presented, from an already-loaded list with no
        // polling) can itself be stale if a background Plaid sync updated a
        // frozen field (e.g. amount) since that list was fetched. Refetching
        // immediately before submit closes that race the same way the
        // equivalent web fix does.
        if case .edit(let existing) = mode, isLocked {
            let listResponse = await client.listTransactions(request: .with { $0.budgetPeriodID = budgetPeriodID })
            let current = listResponse.message?.transactions.first(where: { $0.id == existing.id }) ?? existing
            let request = Wellspent_V1_UpdateTransactionRequest.with {
                $0.id = current.id
                $0.name = current.name
                $0.amount = current.amount
                $0.plannedAmount = current.plannedAmount
                $0.date = current.date
                $0.recurring = current.recurring
                $0.categoryID = categoryID
                $0.paymentMethodID = current.paymentMethodID
                $0.transactionFrequencyID = current.transactionFrequencyID
                $0.transactionTypeID = current.transactionTypeID
            }
            let response = await client.updateTransaction(request: request)
            switch response.result {
            case .success(let message):
                Self.logger.info("locked-edit submit succeeded transactionID=\(existing.id, privacy: .public)")
                return message.transaction
            case .failure(let error):
                errorMessage = error.message ?? "Couldn't update that transaction."
                Self.logger.error("locked-edit submit failed transactionID=\(existing.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
                return nil
            }
        }

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
                Self.logger.info("create submit succeeded transactionID=\(message.transaction.id, privacy: .public)")
                return message.transaction
            case .failure(let error):
                errorMessage = error.message ?? "Couldn't add that transaction."
                Self.logger.error("create submit failed error=\(String(describing: error), privacy: .public)")
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
                Self.logger.info("edit submit succeeded transactionID=\(existing.id, privacy: .public)")
                return message.transaction
            case .failure(let error):
                errorMessage = error.message ?? "Couldn't update that transaction."
                Self.logger.error("edit submit failed transactionID=\(existing.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }
}
