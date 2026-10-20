import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class FixedExpensesViewModel {
    /// `transaction_type` lookup table seed order (see
    /// WellSpent-backend/internal/db/migrations/000001_init_schema.sql):
    /// Fixed = 1, Variable = 2. Raw int32 on the wire, no proto enum.
    static let fixedTypeID: Int32 = 1

    private static let logger = AppLogger.logger("FixedExpenses")

    /// The budget's auto_update_planned_amount setting. Defaults to true,
    /// matching the column default, so the marker doesn't blink off while the
    /// profile loads. Fetched here rather than threaded down — same
    /// per-view-model precedent as AlertsViewModel's own GetMe call.
    private(set) var autoUpdatePlannedAmount = true
    /// Whether the caller has Focused View on — scopes `visibleFixedExpenses`
    /// to their own (or unattributed) templates. `fixedExpenses` itself stays
    /// unfiltered; see `visibleFixedExpenses`.
    private(set) var isFocusedView = false
    private(set) var isLoading = false
    private(set) var transactions: [Wellspent_V1_Transaction] = []
    private(set) var fixedExpenses: [Wellspent_V1_FixedExpense] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    /// Period totals, computed server-side — see `totalText`.
    private(set) var summary: Wellspent_V1_GetExpenseSummaryResponse?
    private(set) var errorMessage: String?

    let budgetPeriodID: String
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let currentUserID: String?

    private let restClient: WellSpentREST.Client

    /// Fixed spend for the period, server-computed. Only paid rows count —
    /// `amount` equals `planned_amount` until a transaction is marked paid, so
    /// an unpaid row would otherwise read as already spent. That rule, and the
    /// exclusion rule beside it, now live in one place instead of being
    /// re-applied here and again on web (#61).
    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: [TransactionAmountFormatting.tuple(from: summary?.fixedActualTotal)],
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
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

        async let fixedExpensesResult = fetchFixedExpenses()
        async let categoriesResult = fetchCategories()
        async let paymentMethodsResult = fetchPaymentMethods()
        async let peopleResult = fetchPeople()
        async let profileResult = fetchProfile()

        if let fetched = await fixedExpensesResult {
            fixedExpenses = fetched
        }
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
        isFocusedView = focusedView
        async let transactionsResult = fetchTransactions(focusedView: focusedView)
        async let summaryResult = fetchSummary(focusedView: focusedView)

        if let fetched = await transactionsResult {
            // Oldest first: the Fixed list is a schedule, so the month should
            // run top to bottom. Variable stays newest-first — it's a feed.
            transactions = fetched.sorted { $0.date.date < $1.date.date }
            Self.logger.info("loaded fixed transactions budgetPeriodID=\(self.budgetPeriodID, privacy: .public) count=\(self.transactions.count, privacy: .public)")
        } else {
            Self.logger.error("failed to load fixed transactions budgetPeriodID=\(self.budgetPeriodID, privacy: .public)")
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

    private func fetchTransactions(focusedView: Bool) async -> [Wellspent_V1_Transaction]? {
        do {
            let output = try await restClient.listTransactions(.init(query: .init(
                budgetPeriodId: budgetPeriodID,
                transactionType: BudgetRESTMapping.restExpenseType(from: Self.fixedTypeID),
                focusedView: focusedView
            )))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load fixed expenses."
                return nil
            }
            return body.transactions.map(BudgetRESTMapping.transaction(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load fixed expenses."
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

    private func fetchFixedExpenses() async -> [Wellspent_V1_FixedExpense]? {
        guard let output = try? await restClient.listFixedExpenses(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.fixedExpenses.map(BudgetRESTMapping.fixedExpense(from:))
    }

    /// Confirmed review matches for this Fixed transaction, rendered as
    /// expandable linked sub-rows (see `TransactionReviewMatching`).
    func linkedReviews(for transaction: Wellspent_V1_Transaction, reviews: [Wellspent_V1_TransactionReview]) -> [Wellspent_V1_TransactionReview] {
        TransactionReviewMatching.linkedReviews(forFixedTransactionID: transaction.id, reviews: reviews)
    }

    /// "N / M payments" progress text for a row's linked template.
    ///
    /// `paymentsMade` is server-computed. It used to be derived here from a
    /// reconstructed anchor date, because `anchor_date` is nullable and the
    /// real fallback — `fixed_expense.created_at` — is not on the wire. Web
    /// guessed differently, so the same bill read `0 / 12` here and `1/12`
    /// there (#61).
    ///
    /// Deliberately silent (no `AppLogger` calls, unlike `template(for:)`):
    /// this runs on every row render, and logging here would spam the log
    /// stream on every scroll rather than only at the meaningful moments.
    func paymentsProgressText(for transaction: Wellspent_V1_Transaction) -> String? {
        guard !transaction.fixedExpenseID.isEmpty,
              let template = fixedExpenses.first(where: { $0.id == transaction.fixedExpenseID }),
              template.totalPayments > 0 else { return nil }
        return "\(template.paymentsMade) / \(template.totalPayments) payments"
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

    /// Fixed-expense templates visible for the Future section — scoped to
    /// the caller's own (or unattributed) bills when Focused View is on.
    /// `fixedExpenses` itself stays unfiltered: `template(for:)` resolves an
    /// already-scoped transaction's template by id and must not fail to
    /// find it on a payment-method-mismatch edge case.
    var visibleFixedExpenses: [Wellspent_V1_FixedExpense] {
        guard isFocusedView else { return fixedExpenses }
        let myPersonID = ChartPreference.myPerson(currentUserID: currentUserID, people: people)?.id
        return fixedExpenses.filter {
            let ownerID = FocusedViewFiltering.ownerID(paymentMethodID: $0.paymentMethodID, paymentMethods: paymentMethods)
            return FocusedViewFiltering.isMineOrUnattributed(ownerID ?? 0, myPersonID: myPersonID)
        }
    }

    /// The template a spawned transaction row came from, for the Edit flow.
    /// Returns `nil` both when the transaction has no linked template at all
    /// and when it does but the template is no longer active (`
    /// ListFixedExpenses` only returns `is_active = true` rows — e.g. a
    /// completed payment plan auto-deactivated it) — callers must handle
    /// `nil` as a real, expected case rather than assuming the lookup always
    /// succeeds for a Fixed transaction.
    func template(for transaction: Wellspent_V1_Transaction) -> Wellspent_V1_FixedExpense? {
        Self.logger.info("looking up template transactionID=\(transaction.id, privacy: .public) fixedExpenseID=\(transaction.fixedExpenseID, privacy: .public)")
        guard !transaction.fixedExpenseID.isEmpty else {
            Self.logger.error("template lookup failed: transaction has no linked fixedExpenseID transactionID=\(transaction.id, privacy: .public)")
            return nil
        }
        guard let template = fixedExpenses.first(where: { $0.id == transaction.fixedExpenseID }) else {
            Self.logger.error("template lookup failed: not found in active templates (deactivated or deleted?) transactionID=\(transaction.id, privacy: .public) fixedExpenseID=\(transaction.fixedExpenseID, privacy: .public) activeTemplateCount=\(self.fixedExpenses.count, privacy: .public)")
            return nil
        }
        return template
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
            replaceTransaction(BudgetRESTMapping.transaction(from: body.transaction))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
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

    /// Deactivates the template (and removes the current period's unpaid
    /// transaction, per the backend's delete semantics) — same
    /// delete-means-deactivate framing as payment methods in 2B-1.
    func delete(_ transaction: Wellspent_V1_Transaction) async {
        guard !transaction.fixedExpenseID.isEmpty else { return }
        if await deleteFixedExpense(id: transaction.fixedExpenseID) {
            transactions.removeAll { $0.id == transaction.id }
        }
    }

    /// Deletes an upcoming template straight from the Future section, where
    /// there is no spawned transaction to act on — the case web has always
    /// supported and iOS didn't (issue #51).
    func deleteTemplate(_ expense: Wellspent_V1_FixedExpense) async {
        _ = await deleteFixedExpense(id: expense.id)
    }

    /// Shared by both delete paths. Returns whether it succeeded, so the
    /// transaction-row caller can also drop its own row.
    private func deleteFixedExpense(id: String) async -> Bool {
        errorMessage = nil
        let fallback = String(
            localized: "Couldn't delete that fixed expense.",
            bundle: AppLanguageStore.currentBundle,
            locale: AppLanguageStore.currentLocale
        )
        do {
            guard case .ok = try await restClient.deleteFixedExpense(.init(path: .init(id: budgetProfileID, feId: id))) else {
                errorMessage = fallback
                Self.logger.error("delete fixed expense failed id=\(id, privacy: .public)")
                return false
            }
            fixedExpenses.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            Self.logger.error("delete fixed expense failed id=\(id, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Seeds state without a network call, so the local-removal behaviour
    /// above is testable. Mirrors `AlertsViewModel.setStateForTesting`.
    func setStateForTesting(
        fixedExpenses: [Wellspent_V1_FixedExpense],
        transactions: [Wellspent_V1_Transaction] = [],
        people: [Wellspent_V1_BudgetPerson] = [],
        paymentMethods: [Wellspent_V1_PaymentMethod] = [],
        isFocusedView: Bool = false
    ) {
        self.fixedExpenses = fixedExpenses
        self.transactions = transactions
        self.people = people
        self.paymentMethods = paymentMethods
        self.isFocusedView = isFocusedView
    }

    private func replaceTransaction(_ transaction: Wellspent_V1_Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }
}
