import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class FixedExpensesViewModel {
    /// `transaction_type` lookup table seed order (see
    /// WellSpent-backend/internal/db/migrations/000001_init_schema.sql):
    /// Fixed = 1, Variable = 2. Raw int32 on the wire, no proto enum.
    static let fixedTypeID: Int32 = 1

    private(set) var isLoading = false
    private(set) var transactions: [Wellspent_V1_Transaction] = []
    private(set) var fixedExpenses: [Wellspent_V1_FixedExpense] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String

    private let client: Wellspent_V1_BudgetServiceClient

    private var incomeCategoryID: Int32? {
        categories.first { $0.isSystem && $0.name == "Income" }?.id
    }

    /// Only paid Fixed transactions count toward the total — `amount` equals
    /// `planned_amount` until a transaction is actually marked paid, so an
    /// unpaid row would otherwise be counted as already spent (matches the
    /// same fix applied to web's `TransactionsPanel.tsx` grand total).
    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: transactions
                .filter { !ExpenseOverviewCalculations.isTransactionExcluded($0, incomeCategoryID: incomeCategoryID) && $0.isPaid }
                .map { (units: $0.amount.units, nanos: $0.amount.nanos) },
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, authenticatedClient: ProtocolClient) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let transactionsResponse = client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = Self.fixedTypeID
        })
        async let fixedExpensesResponse = client.listFixedExpenses(request: .with { $0.budgetProfileID = budgetProfileID })
        async let categoriesResponse = client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await transactionsResponse.result {
        case .success(let message):
            transactions = message.transactions.sorted { $0.date.date > $1.date.date }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load fixed expenses."
        }

        if case .success(let message) = await fixedExpensesResponse.result {
            fixedExpenses = message.expenses
        }
        if case .success(let message) = await categoriesResponse.result {
            categories = message.categories
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
    }

    /// Confirmed review matches for this Fixed transaction, rendered as
    /// expandable linked sub-rows (see `TransactionReviewMatching`).
    func linkedReviews(for transaction: Wellspent_V1_Transaction, reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_TransactionReview] {
        TransactionReviewMatching.linkedReviews(forFixedTransactionID: transaction.id, reviews: reviews)
    }

    func categoryName(for categoryID: Int32) -> String? {
        guard categoryID != 0 else { return nil }
        return categories.first(where: { $0.id == categoryID })?.name
    }

    func paymentMethodName(for paymentMethodID: String) -> String? {
        guard !paymentMethodID.isEmpty else { return nil }
        guard let method = paymentMethods.first(where: { $0.id == paymentMethodID }) else { return nil }
        return method.alias.isEmpty ? method.name : method.alias
    }

    /// The template a spawned transaction row came from, for the Edit flow.
    func template(for transaction: Wellspent_V1_Transaction) -> Wellspent_V1_FixedExpense? {
        guard !transaction.fixedExpenseID.isEmpty else { return nil }
        return fixedExpenses.first(where: { $0.id == transaction.fixedExpenseID })
    }

    /// `CreateFixedExpenseResponse` returns both the new template and the
    /// transaction it spawned in the current period — inserting both
    /// directly avoids a full reload for the common case.
    func addFromCreate(expense: Wellspent_V1_FixedExpense, transaction: Wellspent_V1_Transaction) {
        fixedExpenses.append(expense)
        if !transaction.id.isEmpty {
            transactions.insert(transaction, at: 0)
        }
    }

    /// Editing a template can also adjust the current period's unpaid
    /// transaction server-side, so this reloads everything rather than
    /// trying to reconcile the transaction row locally.
    func handleTemplateUpdated() async {
        await load()
    }

    func markPaid(_ transaction: Wellspent_V1_Transaction, paidAmount: Wellspent_V1_Money, paidAt: Date) async {
        errorMessage = nil
        let request = Wellspent_V1_MarkTransactionAsPaidRequest.with {
            $0.id = transaction.id
            $0.budgetPeriodID = budgetPeriodID
            $0.paidAmount = paidAmount
            $0.paidAt = Google_Protobuf_Timestamp(date: paidAt)
        }
        let response = await client.markTransactionAsPaid(request: request)

        switch response.result {
        case .success(let message):
            replaceTransaction(message.transaction)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't mark that as paid."
        }
    }

    func unmark(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let request = Wellspent_V1_UnmarkTransactionAsPaidRequest.with {
            $0.id = transaction.id
            $0.budgetPeriodID = budgetPeriodID
        }
        let response = await client.unmarkTransactionAsPaid(request: request)

        switch response.result {
        case .success(let message):
            replaceTransaction(message.transaction)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't unmark that transaction."
        }
    }

    func toggleExcluded(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let request = Wellspent_V1_SetTransactionExcludedRequest.with {
            $0.id = transaction.id
            $0.budgetPeriodID = budgetPeriodID
            $0.excluded = !transaction.isExcluded
        }
        let response = await client.setTransactionExcluded(request: request)

        switch response.result {
        case .success:
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                transactions[index].isExcluded.toggle()
            }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that transaction."
        }
    }

    /// Deactivates the template (and removes the current period's unpaid
    /// transaction, per the backend's delete semantics) — same
    /// delete-means-deactivate framing as payment methods in 2B-1.
    func delete(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        guard !transaction.fixedExpenseID.isEmpty else { return }

        let request = Wellspent_V1_DeleteFixedExpenseRequest.with {
            $0.id = transaction.fixedExpenseID
            $0.budgetProfileID = budgetProfileID
        }
        let response = await client.deleteFixedExpense(request: request)

        switch response.result {
        case .success:
            fixedExpenses.removeAll { $0.id == transaction.fixedExpenseID }
            transactions.removeAll { $0.id == transaction.id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that fixed expense."
        }
    }

    private func replaceTransaction(_ transaction: Wellspent_V1_Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }
}
