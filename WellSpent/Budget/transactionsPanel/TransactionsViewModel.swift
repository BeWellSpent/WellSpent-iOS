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

    /// Progress of variable spend against the overall planned total
    /// (`GetExpenseSummary`'s `totalPlanned`), for the Variable tab's summary
    /// card (issue #92). 0 when nothing is planned, so an empty-budget
    /// account never shows a divide-by-zero progress bar.
    var spentProgress: Double {
        let planned = TransactionAmountFormatting.tuple(from: summary?.totalPlanned)
        let plannedValue = Double(planned.units) + Double(planned.nanos) / 1_000_000_000
        guard plannedValue > 0 else { return 0 }
        let spent = TransactionAmountFormatting.tuple(from: summary?.variableActualTotal)
        let spentValue = Double(spent.units) + Double(spent.nanos) / 1_000_000_000
        return min(max(spentValue / plannedValue, 0), 1)
    }

    /// "$X left of $Y planned" for the summary card — reuses the same
    /// server-computed totals `totalText`/`overBudgetTransactionIDs` do.
    var remainingSummaryText: String {
        let planned = TransactionAmountFormatting.tuple(from: summary?.totalPlanned)
        let spent = TransactionAmountFormatting.tuple(from: summary?.variableActualTotal)
        let remaining = TransactionAmountFormatting.sum([planned, (units: -spent.units, nanos: -spent.nanos)])
        let remainingText = MoneyFormatting.format(units: abs(remaining.units), nanos: abs(remaining.nanos), currencyCode: currencyCode, localeIdentifier: localeIdentifier)
        let plannedText = MoneyFormatting.format(units: abs(planned.units), nanos: abs(planned.nanos), currencyCode: currencyCode, localeIdentifier: localeIdentifier)
        return String(localized: "\(remainingText) left of \(plannedText) planned", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    init(budgetPeriodID: String, budgetProfileID: String, currencyCode: String, localeIdentifier: String, currentUserID: String?, restClient: WellSpentREST.Client) {
        self.budgetPeriodID = budgetPeriodID
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.currentUserID = currentUserID
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
        guard let output = try? await restClient.getExpenseSummary(.init(path: .init(id: budgetPeriodID), query: .init(focusedView: focusedView))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return BudgetRESTMapping.expenseSummary(from: body)
    }

    private func fetchTransactions(transactionTypeID: Int32, focusedView: Bool) async -> [Wellspent_V1_Transaction]? {
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

    private func fetchCategories() async -> [Wellspent_V1_Category]? {
        guard let output = try? await restClient.listCategories(.init(query: .init(budgetProfileId: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.categories.map(BudgetRESTMapping.category(from:))
    }

    private func fetchPaymentMethods() async -> [Wellspent_V1_PaymentMethod]? {
        guard let output = try? await restClient.listPaymentMethods(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.methods.map(BudgetRESTMapping.paymentMethod(from:))
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.people.map(BudgetRESTMapping.person(from:))
    }

    /// Card payments, as identified by the system "Payment" category — their
    /// own tab now (issue #76), so they're carved out of the Variable list
    /// below rather than shown there. Loan payments and transfers use
    /// different system categories and stay in Variable.
    private var paymentCategoryID: Int32 {
        categories.first { $0.isSystem(.payment) }?.id ?? -1
    }

    /// Excludes transactions whose review was confirmed — those are shown
    /// instead as a linked sub-row under the matched Fixed transaction (see
    /// `TransactionReviewMatching`) — and card-payment rows, which now live
    /// on their own tab (issue #76).
    func visibleTransactions(reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_Transaction] {
        let confirmedIDs = TransactionReviewMatching.confirmedTransactionIDs(reviews)
        let paymentCategoryID = paymentCategoryID
        return transactions.filter { !confirmedIDs.contains($0.id) && $0.categoryID != paymentCategoryID }
    }

    /// Card-payment rows, carved out of `visibleTransactions` above.
    func paymentTransactions(reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_Transaction] {
        let confirmedIDs = TransactionReviewMatching.confirmedTransactionIDs(reviews)
        let paymentCategoryID = paymentCategoryID
        return transactions.filter { !confirmedIDs.contains($0.id) && $0.categoryID == paymentCategoryID }
    }

    /// Plain client-side sum of the Payments tab's own rows — there's no
    /// server analog; `variableActualTotal` already excludes these from its
    /// own sum (Payment is category-excluded server-side, same as Income)
    /// and is untouched by this.
    func paymentsTotalText(reviews: [Wellspent_V1_TransactionReview]) -> String {
        let amounts = paymentTransactions(reviews: reviews).map { TransactionAmountFormatting.tuple(from: $0.amount) }
        return TransactionAmountFormatting.totalDisplayText(amounts: amounts, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
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
    }

    /// Tap-to-recategorize (issue #92) — reuses the locked-edit, category-only
    /// submit path `AddEditTransactionViewModel` already has for archived/
    /// Plaid-imported transactions (a plain category change is the same
    /// shape), instead of a second hand-written category-only RPC call.
    func updateCategory(for transaction: Wellspent_V1_Transaction, to categoryID: Int32) async {
        errorMessage = nil
        let editViewModel = AddEditTransactionViewModel(
            mode: .edit(transaction),
            budgetPeriodID: budgetPeriodID,
            currencyCode: currencyCode,
            forceLocked: true,
            restClient: restClient
        )
        editViewModel.categoryID = categoryID
        if let updated = await editViewModel.submit() {
            replaceTransaction(updated)
        } else {
            errorMessage = editViewModel.errorMessage ?? "Couldn't update that transaction."
        }
    }

    func toggleExcluded(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let fallback = "Couldn't update that transaction."
        let newExcluded = !transaction.isExcluded
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
    }

    /// Seeds state without a network call, so the partition logic above is
    /// testable. Mirrors `FixedExpensesViewModel.setStateForTesting`.
    func setStateForTesting(transactions: [Wellspent_V1_Transaction], categories: [Wellspent_V1_Category] = []) {
        self.transactions = transactions
        self.categories = categories
    }

    func delete(id: String) async {
        errorMessage = nil
        let fallback = "Couldn't delete that transaction."
        do {
            guard case .ok = try await restClient.deleteTransaction(.init(path: .init(id: id))) else {
                errorMessage = fallback
                return
            }
            transactions.removeAll { $0.id == id }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
        }
    }
}
