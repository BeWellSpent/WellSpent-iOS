import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

/// The Reports tab: Commitments and Category trends (docs/features/reports.md).
/// Every figure comes from the two report endpoints; the budget's people,
/// categories, payment methods and fixed expenses are only for labels,
/// colours, the person filter and the payment-plan rows.
@MainActor
@Observable
final class ReportsViewModel {
    enum Tab: Hashable {
        case commitments
        case trends
    }

    var tab: Tab = .commitments
    var showPercent = false
    private(set) var personID: Int64?
    private(set) var range = ReportsCalculations.freeMaxRange
    private(set) var isPro = false
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var fixedExpenses: [Wellspent_V1_FixedExpense] = []
    private(set) var commitments: ReportsRESTMapping.Commitments?
    private(set) var trends: ReportsRESTMapping.Trends?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    private let restClient: WellSpentREST.Client
    private static let logger = AppLogger.logger("Reports")

    init(budgetProfileID: String, currencyCode: String, localeIdentifier: String, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let user = await UserRESTMapping.currentUser(restClient: restClient) {
            isPro = user.plan == .pro || user.plan == .lifetime
        }
        async let peopleResult = fetchPeople()
        async let categoriesResult = fetchCategories()
        async let methodsResult = fetchPaymentMethods()
        async let fixedResult = fetchFixedExpenses()
        people = await peopleResult ?? people
        categories = await categoriesResult ?? categories
        paymentMethods = await methodsResult ?? paymentMethods
        fixedExpenses = await fixedResult ?? fixedExpenses
        await loadReports()
    }

    func selectPerson(_ id: Int64?) async {
        guard id != personID else { return }
        personID = id
        await loadReports()
    }

    /// A range Free can't open is ignored; the control shows it locked.
    func selectRange(_ newRange: Int) async {
        guard newRange != range, !ReportsCalculations.isRangeLocked(newRange, isPro: isPro) else { return }
        range = newRange
        await loadTrends()
    }

    func loadReports() async {
        errorMessage = nil
        async let commitmentsLoad: Void = loadCommitments()
        async let trendsLoad: Void = loadTrends()
        _ = await (commitmentsLoad, trendsLoad)
    }

    // MARK: Labels and the payment-plan rows

    func categoryName(_ id: Int32) -> String {
        if id == 0 { return String(localized: "Uncategorized", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale) }
        return categories.first { $0.id == id }?.displayName
            ?? String(localized: "Other", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    func categoryColor(_ id: Int32) -> String {
        categories.first { $0.id == id }?.color ?? HomeOverviewCalculations.otherSegmentColorHex
    }

    /// Payment plans and installments, for the selected person by their payment method.
    var plans: [Wellspent_V1_FixedExpense] {
        fixedExpenses
            .filter { FixedExpensePlanSummary.kind(for: $0) != nil && belongsToSelectedPerson(paymentMethodID: $0.paymentMethodID) }
            .sorted { ($0.hasEndDate ? $0.endDate.dateOnly : .distantFuture) < ($1.hasEndDate ? $1.endDate.dateOnly : .distantFuture) }
    }

    // MARK: Drill-through

    /// The rows behind a category in a period, for the selected person.
    func transactions(periodID: String, categoryID: Int32, fixedOnly: Bool) async -> [Wellspent_V1_Transaction] {
        do {
            let output = try await restClient.listTransactions(.init(query: .init(budgetPeriodId: periodID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                RESTNetworkError.logUnexpectedOutput(output)
                return []
            }
            return body.transactions.map(BudgetRESTMapping.transaction(from:)).filter {
                $0.categoryID == categoryID
                    && !$0.isExcluded
                    && (!fixedOnly || $0.transactionTypeID == TransactionsViewModel.fixedTypeID)
                    && belongsToSelectedPerson(paymentMethodID: $0.paymentMethodID)
            }
        } catch {
            _ = RESTNetworkError.connectivityMessage(for: error)
            Self.logger.error("report drill-through failed periodId=\(periodID, privacy: .public) categoryId=\(categoryID, privacy: .public)")
            return []
        }
    }

    private func belongsToSelectedPerson(paymentMethodID: String) -> Bool {
        guard let personID else { return true }
        return paymentMethods.first { $0.id == paymentMethodID }?.budgetPersonID == personID
    }

    // MARK: Loading

    private func loadCommitments() async {
        do {
            let output = try await restClient.getCommitmentReport(.init(path: .init(id: budgetProfileID), query: .init(budgetPersonId: personID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                RESTNetworkError.logUnexpectedOutput(output)
                errorMessage = String(localized: "Couldn't load your reports.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                return
            }
            commitments = ReportsRESTMapping.commitments(from: body)
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error)
                ?? String(localized: "Couldn't load your reports.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
    }

    private func loadTrends() async {
        do {
            let output = try await restClient.getCategoryTrends(.init(path: .init(id: budgetProfileID), query: .init(periods: Int32(range), budgetPersonId: personID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                RESTNetworkError.logUnexpectedOutput(output)
                errorMessage = String(localized: "Couldn't load your reports.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                return
            }
            trends = ReportsRESTMapping.trends(from: body)
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error)
                ?? String(localized: "Couldn't load your reports.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.people.map(BudgetRESTMapping.person(from:))
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

    private func fetchFixedExpenses() async -> [Wellspent_V1_FixedExpense]? {
        guard let output = try? await restClient.listFixedExpenses(.init(path: .init(id: budgetProfileID), query: .init())),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.fixedExpenses.map(BudgetRESTMapping.fixedExpense(from:))
    }
}
