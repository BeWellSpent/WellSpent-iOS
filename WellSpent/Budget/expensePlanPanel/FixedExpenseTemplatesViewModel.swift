import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

/// Plan's Fixed Expenses sub-tab — profile-level recurring-bill template
/// management (create/edit/deactivate), not a period's spawned occurrences
/// (that's Overview's Transactions sub-tab, backed by `TransactionsViewModel`).
///
/// Replaces the old `FixedExpensesViewModel`, which this screen deliberately
/// does not reuse: that view model's period-scoped state (spawned
/// transactions, mark-paid/unmark, `GetExpenseSummary` totals) has no meaning
/// for a template-management list with no period in view. See
/// docs/features/overview-plan-navigation-rework.md's Stage 3 notes.
@MainActor
@Observable
final class FixedExpenseTemplatesViewModel {
    private static let logger = AppLogger.logger("FixedExpenseTemplates")

    private(set) var isLoading = false
    private(set) var fixedExpenses: [Wellspent_V1_FixedExpense] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    /// `remainingBalance` has no proto equivalent, keyed by fixed expense id —
    /// see `BudgetRESTMapping.FixedExpensePayoffInfo`. Needed so Edit's "Pay
    /// in Full" sheet still works from here.
    private(set) var payoffByFixedExpenseID: [String: BudgetRESTMapping.FixedExpensePayoffInfo] = [:]
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let currentUserID: String?

    private let restClient: WellSpentREST.Client

    init(budgetProfileID: String, currencyCode: String, localeIdentifier: String, currentUserID: String?, restClient: WellSpentREST.Client) {
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

        if let fetched = await categoriesResult { categories = fetched }
        if let fetched = await paymentMethodsResult { paymentMethods = fetched }
        if let fetched = await peopleResult { people = fetched }

        // Needs `people` resolved first, so this can't join the batch above.
        let focusedView = ChartPreference.myPerson(currentUserID: currentUserID, people: people)?.focusedViewEnabled ?? false
        if let fetched = await fetchFixedExpenses(focusedView: focusedView) {
            fixedExpenses = fetched
        }
    }

    private func fetchFixedExpenses(focusedView: Bool) async -> [Wellspent_V1_FixedExpense]? {
        do {
            let output = try await restClient.listFixedExpenses(.init(
                path: .init(id: budgetProfileID),
                query: .init(focusedView: focusedView)
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load fixed expenses."
                Self.logger.error("load fixed expense templates failed budgetProfileID=\(self.budgetProfileID, privacy: .public)")
                return nil
            }
            payoffByFixedExpenseID = Dictionary(uniqueKeysWithValues: body.fixedExpenses.map { ($0.id, BudgetRESTMapping.fixedExpensePayoffInfo(from: $0)) })
            Self.logger.info("loaded fixed expense templates budgetProfileID=\(self.budgetProfileID, privacy: .public) count=\(body.fixedExpenses.count, privacy: .public)")
            return body.fixedExpenses.map(BudgetRESTMapping.fixedExpense(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load fixed expenses."
            Self.logger.error("load fixed expense templates failed budgetProfileID=\(self.budgetProfileID, privacy: .public) error=\(String(describing: error), privacy: .public)")
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

    /// Prefill for the "Pay in full" sheet — zero when no payoff data has
    /// loaded yet (e.g. a freshly created template).
    func remainingBalance(for fixedExpenseID: String) -> Wellspent_V1_Money {
        payoffByFixedExpenseID[fixedExpenseID]?.remainingBalance ?? Wellspent_V1_Money()
    }

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

    /// `CreateFixedExpenseResponse` also returns the transaction it spawned
    /// in the current period — irrelevant here (this list isn't period-
    /// scoped), so only the template is kept.
    func addTemplate(_ expense: Wellspent_V1_FixedExpense) {
        fixedExpenses.append(expense)
    }

    func replaceTemplate(_ expense: Wellspent_V1_FixedExpense) {
        guard let index = fixedExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        fixedExpenses[index] = expense
    }

    /// Deactivates the template — same delete-means-deactivate framing the
    /// former `FixedExpensesViewModel.deleteTemplate` had.
    func deleteTemplate(_ expense: Wellspent_V1_FixedExpense) async {
        errorMessage = nil
        let fallback = String(
            localized: "Couldn't delete that fixed expense.",
            bundle: AppLanguageStore.currentBundle,
            locale: AppLanguageStore.currentLocale
        )
        do {
            guard case .ok = try await restClient.deleteFixedExpense(.init(path: .init(id: budgetProfileID, feId: expense.id))) else {
                errorMessage = fallback
                Self.logger.error("delete fixed expense template failed id=\(expense.id, privacy: .public)")
                return
            }
            fixedExpenses.removeAll { $0.id == expense.id }
            Self.logger.info("delete fixed expense template succeeded id=\(expense.id, privacy: .public)")
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            Self.logger.error("delete fixed expense template failed id=\(expense.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    /// Seeds state without a network call, so the add/replace/delete logic
    /// is testable. Mirrors the former `FixedExpensesViewModel.setStateForTesting`.
    func setStateForTesting(fixedExpenses: [Wellspent_V1_FixedExpense]) {
        self.fixedExpenses = fixedExpenses
    }
}
