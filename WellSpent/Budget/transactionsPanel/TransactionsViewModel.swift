import Observation
import WellSpentAPI

@MainActor
@Observable
final class TransactionsViewModel {
    /// `transaction_type` lookup table seed order (see
    /// WellSpent-backend/internal/db/migrations/000001_init_schema.sql):
    /// Fixed = 1, Variable = 2. Raw int32 on the wire, no proto enum.
    static let variableTypeID: Int32 = 2

    private(set) var isLoading = false
    private(set) var transactions: [Wellspent_V1_Transaction] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String

    private let client: Wellspent_V1_BudgetServiceClient

    /// Sum of every non-excluded transaction's signed amount, formatted.
    /// Doesn't yet special-case the system "Income" category the way web
    /// does (see CLAUDE.md) — deferred, not forgotten.
    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: transactions.filter { !$0.isExcluded }.map { (units: $0.amount.units, nanos: $0.amount.nanos) },
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
            $0.transactionTypeID = Self.variableTypeID
        })
        async let categoriesResponse = client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await transactionsResponse.result {
        case .success(let message):
            transactions = message.transactions.sorted { $0.date.date > $1.date.date }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load transactions."
        }

        if case .success(let message) = await categoriesResponse.result {
            categories = message.categories
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
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

    func addTransaction(_ transaction: Wellspent_V1_Transaction) {
        transactions.insert(transaction, at: 0)
    }

    func replaceTransaction(_ transaction: Wellspent_V1_Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
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

    func delete(id: String) async {
        errorMessage = nil
        let request = Wellspent_V1_DeleteTransactionRequest.with {
            $0.id = id
            $0.budgetPeriodID = budgetPeriodID
        }
        let response = await client.deleteTransaction(request: request)

        switch response.result {
        case .success:
            transactions.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that transaction."
        }
    }
}
