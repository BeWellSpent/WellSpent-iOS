import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

/// The Reports tab: Category trends (docs/features/reports.md). Every figure
/// comes from the report endpoint; the budget's people, categories and payment
/// methods are only for labels, colours and the person filter.
@MainActor
@Observable
final class ReportsViewModel {
    var showPercent = false
    private(set) var personID: Int64?
    private(set) var range = ReportsCalculations.freeMaxRange
    private(set) var isPro = false
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
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
        people = await peopleResult ?? people
        categories = await categoriesResult ?? categories
        paymentMethods = await methodsResult ?? paymentMethods
        await loadTrends()
    }

    func selectPerson(_ id: Int64?) async {
        guard id != personID else { return }
        personID = id
        await loadTrends()
    }

    /// A range Free can't open is ignored; the control shows it locked.
    func selectRange(_ newRange: Int) async {
        guard newRange != range, !ReportsCalculations.isRangeLocked(newRange, isPro: isPro) else { return }
        range = newRange
        await loadTrends()
    }

    // MARK: Labels

    func categoryName(_ id: Int32) -> String {
        if id == 0 { return String(localized: "Uncategorized", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale) }
        return categories.first { $0.id == id }?.displayName
            ?? String(localized: "Other", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    func categoryColor(_ id: Int32) -> String {
        categories.first { $0.id == id }?.color ?? HomeOverviewCalculations.otherSegmentColorHex
    }

    // MARK: Drill-through

    /// The rows behind a category in a period, for the selected person.
    func transactions(periodID: String, categoryID: Int32) async -> [Wellspent_V1_Transaction] {
        do {
            let output = try await restClient.listTransactions(.init(query: .init(budgetPeriodId: periodID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                RESTNetworkError.logUnexpectedOutput(output)
                return []
            }
            return body.transactions.map(BudgetRESTMapping.transaction(from:)).filter {
                $0.categoryID == categoryID
                    && !$0.isExcluded
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

    private func loadTrends() async {
        errorMessage = nil
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
}
