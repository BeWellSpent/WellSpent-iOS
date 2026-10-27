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
    static let fixedTypeID: Int32 = 1

    private(set) var isLoading = false
    /// Now both Variable and Fixed (Stage 2 of
    /// docs/features/overview-plan-navigation-rework.md merged them into one
    /// list) — `fetchTransactions` no longer filters by `transactionType`.
    private(set) var transactions: [Wellspent_V1_Transaction] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    /// Fixed-expense templates — needed by a Fixed row's payments-progress
    /// caption now that the merged list renders Fixed rows directly.
    private(set) var fixedExpenses: [Wellspent_V1_FixedExpense] = []
    /// The budget's auto_update_planned_amount setting, for a Fixed row's
    /// re-plan marker.
    private(set) var autoUpdatePlannedAmount = true
    /// `remainingBalance`/`paidOffDate` have no proto equivalent, keyed by
    /// fixed expense id — see `BudgetRESTMapping.FixedExpensePayoffInfo`.
    private(set) var payoffByFixedExpenseID: [String: BudgetRESTMapping.FixedExpensePayoffInfo] = [:]
    /// Transactions whose payment brought their plan's balance to zero early.
    private(set) var paidOffEarlyTransactionIDs: Set<String> = []
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

    /// Combined Fixed+Variable spend for the period, server-computed under
    /// the same exclusion rule as everywhere else. The merged list (Stage 2)
    /// shows both in one list now, so the summary card's total has to cover
    /// both rather than Variable alone — summing the two server totals here
    /// instead of re-deriving either would put a second spelling of the
    /// number next to the totals the Plan and Overview tabs print.
    private var combinedActualTotal: (units: Int64, nanos: Int32) {
        TransactionAmountFormatting.sum([
            TransactionAmountFormatting.tuple(from: summary?.variableActualTotal),
            TransactionAmountFormatting.tuple(from: summary?.fixedActualTotal)
        ])
    }

    var totalText: String {
        TransactionAmountFormatting.magnitudeDisplayText(
            amounts: [combinedActualTotal],
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }

    /// Progress of combined spend against the overall planned total
    /// (`GetExpenseSummary`'s `totalPlanned`), for the summary card (issue
    /// #92). 0 when nothing is planned, so an empty-budget account never
    /// shows a divide-by-zero progress bar.
    var spentProgress: Double {
        let planned = TransactionAmountFormatting.tuple(from: summary?.totalPlanned)
        let plannedValue = Double(planned.units) + Double(planned.nanos) / 1_000_000_000
        guard plannedValue > 0 else { return 0 }
        let spent = combinedActualTotal
        let spentValue = Double(spent.units) + Double(spent.nanos) / 1_000_000_000
        return min(max(spentValue / plannedValue, 0), 1)
    }

    /// "$X left of $Y planned" for the summary card — reuses the same
    /// server-computed totals `totalText`/`overBudgetTransactionIDs` do.
    var remainingSummaryText: String {
        let planned = TransactionAmountFormatting.tuple(from: summary?.totalPlanned)
        let spent = combinedActualTotal
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
        async let profileResult = fetchProfile()

        if let fetched = await categoriesResult {
            categories = fetched
        }
        if let fetched = await paymentMethodsResult {
            paymentMethods = fetched
        }
        if let fetched = await peopleResult {
            people = fetched
        }
        if let fetched = await profileResult {
            autoUpdatePlannedAmount = fetched.autoUpdatePlannedAmount
        }

        // Needs `people` resolved first, so these can't join the batch above.
        let focusedView = ChartPreference.myPerson(currentUserID: currentUserID, people: people)?.focusedViewEnabled ?? false
        async let transactionsResult = fetchTransactions(focusedView: focusedView)
        async let summaryResult = fetchSummary(focusedView: focusedView)
        async let fixedExpensesResult = fetchFixedExpenses(focusedView: focusedView)

        if let fetched = await transactionsResult {
            transactions = fetched.sorted { $0.date.date > $1.date.date }
        }

        if let fetched = await summaryResult {
            summary = fetched
        }

        if let fetched = await fixedExpensesResult {
            fixedExpenses = fetched
        }
    }

    private func fetchSummary(focusedView: Bool) async -> Wellspent_V1_GetExpenseSummaryResponse? {
        guard let output = try? await restClient.getExpenseSummary(.init(path: .init(id: budgetPeriodID), query: .init(focusedView: focusedView))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return BudgetRESTMapping.expenseSummary(from: body)
    }

    /// No `transactionType` filter — Stage 2 of the Overview/Plan nav rework
    /// merged Variable and Fixed into one list, so this fetches both in one
    /// call (same shape `ExpenseOverviewViewModel.fetchTransactions` already
    /// uses).
    private func fetchTransactions(focusedView: Bool) async -> [Wellspent_V1_Transaction]? {
        do {
            let output = try await restClient.listTransactions(.init(query: .init(
                budgetPeriodId: budgetPeriodID,
                focusedView: focusedView
            )))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load transactions."
                return nil
            }
            paidOffEarlyTransactionIDs = Set(body.transactions.filter(BudgetRESTMapping.isFixedExpensePaidOffEarly(from:)).map(\.id))
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

    private func fetchProfile() async -> Wellspent_V1_BudgetProfile? {
        guard let output = try? await restClient.getBudgetProfile(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return BudgetRESTMapping.profile(from: body.profile)
    }

    private func fetchFixedExpenses(focusedView: Bool) async -> [Wellspent_V1_FixedExpense]? {
        guard let output = try? await restClient.listFixedExpenses(.init(
            path: .init(id: budgetProfileID),
            query: .init(focusedView: focusedView)
        )), case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        payoffByFixedExpenseID = Dictionary(uniqueKeysWithValues: body.fixedExpenses.map { ($0.id, BudgetRESTMapping.fixedExpensePayoffInfo(from: $0)) })
        return body.fixedExpenses.map(BudgetRESTMapping.fixedExpense(from:))
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
        return TransactionAmountFormatting.magnitudeDisplayText(amounts: amounts, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
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

    /// "N / M payments" progress text for a Fixed row's linked template.
    /// Needed here since the merged list (Stage 2) renders Fixed rows
    /// directly rather than delegating to a separate view model.
    /// Deliberately silent (no `AppLogger` calls): runs on every row render.
    func paymentsProgressText(for transaction: Wellspent_V1_Transaction) -> String? {
        guard !transaction.fixedExpenseID.isEmpty,
              let template = fixedExpenses.first(where: { $0.id == transaction.fixedExpenseID }),
              template.totalPayments > 0 else { return nil }
        return "\(template.paymentsMade) / \(template.totalPayments) payments"
    }

    func isPaidOffEarly(_ transaction: Wellspent_V1_Transaction) -> Bool {
        paidOffEarlyTransactionIDs.contains(transaction.id)
    }

    /// Confirmed review matches for a Fixed transaction, rendered as an
    /// expandable linked sub-row — see `TransactionReviewMatching`.
    func linkedReviews(for transaction: Wellspent_V1_Transaction, reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_TransactionReview] {
        TransactionReviewMatching.linkedReviews(forFixedTransactionID: transaction.id, reviews: reviews)
    }

    func addTransaction(_ transaction: Wellspent_V1_Transaction) {
        transactions.insert(transaction, at: 0)
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
    /// testable.
    func setStateForTesting(
        transactions: [Wellspent_V1_Transaction],
        categories: [Wellspent_V1_Category] = [],
        fixedExpenses: [Wellspent_V1_FixedExpense] = []
    ) {
        self.transactions = transactions
        self.categories = categories
        self.fixedExpenses = fixedExpenses
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

    // MARK: Fixed-row occurrence actions (merged list, Stage 2)
    //
    // Mark Paid/Unmark/Exclude/Delete-this-occurrence only — editing the
    // underlying recurring template is deliberately not reachable from this
    // list (see `TransactionsListView`'s Fixed-row swipe actions). Template
    // management itself lives in Plan's Fixed Expenses sub-tab
    // (`FixedExpenseTemplatesViewModel`).

    func markPaid(_ transaction: Wellspent_V1_Transaction, paidAmount: Wellspent_V1_Money, paidAt: Date) async {
        errorMessage = nil
        let fallback = "Couldn't mark that as paid."
        do {
            let output = try await restClient.markTransactionAsPaid(.init(
                path: .init(id: transaction.id),
                body: .json(.init(
                    budgetPeriodId: budgetPeriodID,
                    paidAmount: BudgetRESTMapping.restMoney(from: paidAmount),
                    paidDate: Google_Protobuf_Timestamp(dateOnly: paidAt).restDateString
                ))
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                return
            }
            setPaidOffEarly(BudgetRESTMapping.isFixedExpensePaidOffEarly(from: body.transaction), for: body.transaction.id)
            replaceTransaction(BudgetRESTMapping.transaction(from: body.transaction))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
        }
    }

    func unmark(_ transaction: Wellspent_V1_Transaction) async {
        errorMessage = nil
        let fallback = "Couldn't unmark that transaction."
        do {
            let output = try await restClient.unmarkTransactionAsPaid(.init(
                path: .init(id: transaction.id),
                body: .json(.init(budgetPeriodId: budgetPeriodID))
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                return
            }
            setPaidOffEarly(BudgetRESTMapping.isFixedExpensePaidOffEarly(from: body.transaction), for: body.transaction.id)
            replaceTransaction(BudgetRESTMapping.transaction(from: body.transaction))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
        }
    }

    /// Deactivates the Fixed row's linked template (and removes this
    /// period's unpaid transaction, per the backend's delete semantics) —
    /// same delete-means-deactivate framing payment methods already use.
    func delete(_ transaction: Wellspent_V1_Transaction) async {
        guard !transaction.fixedExpenseID.isEmpty else { return }
        errorMessage = nil
        let fallback = String(localized: "Couldn't delete that fixed expense.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        do {
            guard case .ok = try await restClient.deleteFixedExpense(.init(path: .init(id: budgetProfileID, feId: transaction.fixedExpenseID))) else {
                errorMessage = fallback
                return
            }
            fixedExpenses.removeAll { $0.id == transaction.fixedExpenseID }
            transactions.removeAll { $0.id == transaction.id }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
        }
    }

    private func setPaidOffEarly(_ paidOffEarly: Bool, for transactionID: String) {
        if paidOffEarly {
            paidOffEarlyTransactionIDs.insert(transactionID)
        } else {
            paidOffEarlyTransactionIDs.remove(transactionID)
        }
    }
}
