import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

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
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    /// Totals and the over-budget set, computed server-side. Replaces four
    /// fetches (allocations, savings sources, fixed transactions, and the
    /// planned-total rule applied to them) that existed only to rebuild
    /// figures this one response already carries.
    private(set) var summary: Wellspent_V1_GetExpenseSummaryResponse?
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let currentUserID: String?

    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    /// Which transactions crossed their category's plan — server-computed.
    ///
    /// This used to walk the transactions locally against a baseline built
    /// from `ExpensePlanCalculations.plannedTotal`, the last surviving copy of
    /// the math `GetExpenseSummary` replaced everywhere else (issue #35). Web
    /// built its own too, and the two disagreed on whether an allocation and a
    /// fixed bill in one category add together or fall back. Now neither
    /// derives it (#61).
    var overBudgetTransactionIDs: Set<String> {
        Set(summary?.overBudgetTransactionIds ?? [])
    }

    /// Variable spend for the period, server-computed under the same
    /// exclusion rule as everywhere else — manually excluded rows and the
    /// system "Income" category never count. Summing the fetched rows here
    /// instead would put a second spelling of the number next to the totals
    /// the Plan and Overview tabs print.
    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: [TransactionAmountFormatting.tuple(from: summary?.variableActualTotal)],
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, currentUserID: String?, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let categoriesResult = fetchCategories()
        async let paymentMethodsResult = fetchPaymentMethods()
        async let peopleResult = fetchPeople()

        if let fetched = await categoriesResult {
            categories = fetched
        }
        if let fetched = await paymentMethodsResult {
            paymentMethods = fetched
        }
        if let fetched = await peopleResult {
            people = fetched
        }

        // Needs `people` resolved first, so these can't join the batch above.
        let focusedView = ChartPreference.myPerson(currentUserID: currentUserID, people: people)?.focusedViewEnabled ?? false
        async let transactionsResult = fetchTransactions(transactionTypeID: Self.variableTypeID, focusedView: focusedView)
        async let summaryResult = fetchSummary(focusedView: focusedView)

        if let fetched = await transactionsResult {
            transactions = fetched.sorted { $0.date.date > $1.date.date }
        }

        if let fetched = await summaryResult {
            summary = fetched
        }
    }

    private func fetchSummary(focusedView: Bool) async -> Wellspent_V1_GetExpenseSummaryResponse? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.getExpenseSummary(.init(path: .init(id: budgetPeriodID), query: .init(focusedView: focusedView))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return BudgetRESTMapping.expenseSummary(from: body)
        }
        guard case .success(let message) = await client.getExpenseSummary(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.focusedView = focusedView
        }).result else { return nil }
        return message
    }

    private func fetchTransactions(transactionTypeID: Int32, focusedView: Bool) async -> [Wellspent_V1_Transaction]? {
        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.listTransactions(.init(query: .init(
                    budgetPeriodId: budgetPeriodID,
                    transactionType: BudgetRESTMapping.restExpenseType(from: transactionTypeID),
                    focusedView: focusedView
                )))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load transactions."
                    return nil
                }
                return body.transactions.map(BudgetRESTMapping.transaction(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load transactions."
                return nil
            }
        }
        let response = await client.listTransactions(request: .with {
            $0.budgetPeriodID = budgetPeriodID
            $0.transactionTypeID = transactionTypeID
            $0.focusedView = focusedView
        })
        switch response.result {
        case .success(let message):
            return message.transactions
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load transactions."
            return nil
        }
    }

    private func fetchCategories() async -> [Wellspent_V1_Category]? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.listCategories(.init(query: .init(budgetProfileId: budgetProfileID))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return body.categories.map(BudgetRESTMapping.category(from:))
        }
        guard case .success(let message) = await client.listCategories(request: .with { $0.budgetProfileID = budgetProfileID }).result else {
            return nil
        }
        return message.categories
    }

    private func fetchPaymentMethods() async -> [Wellspent_V1_PaymentMethod]? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.listPaymentMethods(.init(path: .init(id: budgetProfileID))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return body.methods.map(BudgetRESTMapping.paymentMethod(from:))
        }
        guard case .success(let message) = await client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID }).result else {
            return nil
        }
        return message.methods
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return body.people.map(BudgetRESTMapping.person(from:))
        }
        guard case .success(let message) = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID }).result else {
            return nil
        }
        return message.people
    }

    /// Excludes transactions whose review was confirmed — those are shown
    /// instead as a linked sub-row under the matched Fixed transaction (see
    /// `TransactionReviewMatching`).
    func visibleTransactions(reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_Transaction] {
        let confirmedIDs = TransactionReviewMatching.confirmedTransactionIDs(reviews)
        return transactions.filter { !confirmedIDs.contains($0.id) }
    }

    func pendingMatchName(for transaction: Wellspent_V1_Transaction, reviews: [Wellspent_V1_TransactionReview]) -> String? {
        TransactionReviewMatching.pendingMatchName(forTransactionID: transaction.id, reviews: reviews)
    }

    /// The translated name, so a row's caption and the search that has to
    /// match it both use what is actually on screen.
    func categoryName(for categoryID: Int32) -> String? {
        guard categoryID != 0 else { return nil }
        return categories.first(where: { $0.id == categoryID })?.displayName
    }

    func categoryColor(for categoryID: Int32) -> String {
        categories.first(where: { $0.id == categoryID })?.color ?? ""
    }

    func paymentMethodName(for paymentMethodID: String) -> String? {
        guard !paymentMethodID.isEmpty else { return nil }
        guard let method = paymentMethods.first(where: { $0.id == paymentMethodID }) else { return nil }
        return method.alias.isEmpty ? method.name : method.alias
    }

    func paymentMethodColor(for paymentMethodID: String) -> String {
        paymentMethods.first(where: { $0.id == paymentMethodID })?.color ?? ""
    }

    /// Resolves a transaction's owner via its payment method's attributed
    /// person — mirrors web's `resolveOwnerName`. Used by search, not display.
    func ownerName(for paymentMethodID: String) -> String? {
        guard !paymentMethodID.isEmpty else { return nil }
        guard let method = paymentMethods.first(where: { $0.id == paymentMethodID }), method.budgetPersonID != 0 else { return nil }
        return people.first(where: { $0.id == method.budgetPersonID })?.userName
    }

    func addTransaction(_ transaction: Wellspent_V1_Transaction) {
        transactions.insert(transaction, at: 0)
    }

    func replaceTransaction(_ transaction: Wellspent_V1_Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }

    /// Reverses an installment split. The backend refuses once any payment has
    /// been marked paid — real recorded spend shouldn't vanish into an undo —
    /// so that failure is an expected outcome here and its message is shown
    /// as-is rather than replaced with a generic one.
    ///
    /// Reloads rather than patching local state: the plan's spawned payments
    /// are deleted server-side too, and they may sit in periods this list
    /// isn't showing.
    func deleteInstallmentPlan(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let fallback = String(localized: "Couldn't undo the split.", locale: AppLanguageStore.currentLocale)

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.deleteInstallmentPlan(.init(
                    path: .init(id: transaction.id),
                    query: .init(budgetPeriodId: budgetPeriodID)
                )) else {
                    errorMessage = fallback
                    return
                }
                await load()
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

        let response = await client.deleteInstallmentPlan(request: .with {
            $0.transactionID = transaction.id
            $0.budgetPeriodID = budgetPeriodID
        })

        switch response.result {
        case .success:
            await load()
        case .failure(let error):
            errorMessage = error.message ?? fallback
        }
    }

    func toggleExcluded(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let fallback = "Couldn't update that transaction."
        let newExcluded = !transaction.isExcluded

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.setTransactionExcluded(.init(
                    path: .init(id: transaction.id),
                    body: .json(.init(budgetPeriodId: budgetPeriodID, excluded: newExcluded))
                )) else {
                    errorMessage = fallback
                    return
                }
                if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                    transactions[index].isExcluded = newExcluded
                }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

        let request = Wellspent_V1_SetTransactionExcludedRequest.with {
            $0.id = transaction.id
            $0.budgetPeriodID = budgetPeriodID
            $0.excluded = newExcluded
        }
        let response = await client.setTransactionExcluded(request: request)

        switch response.result {
        case .success:
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                transactions[index].isExcluded.toggle()
            }
        case .failure(let error):
            errorMessage = error.message ?? fallback
        }
    }

    func delete(id: String) async {
        errorMessage = nil
        let fallback = "Couldn't delete that transaction."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.deleteTransaction(.init(path: .init(id: id))) else {
                    errorMessage = fallback
                    return
                }
                transactions.removeAll { $0.id == id }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

        let request = Wellspent_V1_DeleteTransactionRequest.with {
            $0.id = id
            $0.budgetPeriodID = budgetPeriodID
        }
        let response = await client.deleteTransaction(request: request)

        switch response.result {
        case .success:
            transactions.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? fallback
        }
    }
}
