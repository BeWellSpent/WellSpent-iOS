import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

/// Backs `PeriodReviewGateView` — the blocking screen shown when a period's
/// `needsReview` is true (a genuine cycle, not a profile's first period).
/// See docs/features/month-cycling-review.md.
///
/// Owns only the "carried over" list, which is specific to this screen —
/// everything else a user needs to review (the previous period's Fixed and
/// Variable transactions, with the same swipe actions/mark-paid/exclude/
/// Plaid lock as anywhere else in the app) is the *real* Transactions list,
/// embedded via `PeriodReviewTransactionsView`, not re-derived here.
@MainActor
@Observable
final class PeriodReviewViewModel {
    private static let logger = AppLogger.logger("PeriodReview")

    private(set) var period: Wellspent_V1_BudgetPeriod
    let previousPeriod: Wellspent_V1_BudgetPeriod?
    private let budgetProfileID: String
    private let restClient: WellSpentREST.Client

    private(set) var carriedOverTransactions: [Wellspent_V1_Transaction] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var isLoading = false
    private(set) var isConfirming = false
    private(set) var isRetriggering = false
    var errorMessage: String?

    init(period: Wellspent_V1_BudgetPeriod, previousPeriod: Wellspent_V1_BudgetPeriod?, budgetProfileID: String, restClient: WellSpentREST.Client) {
        self.period = period
        self.previousPeriod = previousPeriod
        self.budgetProfileID = budgetProfileID
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let previousPeriod else {
            // No previous period to carry anything from — shouldn't happen
            // for a row the backend flagged `needsReview`, but leaves the
            // list empty rather than crashing on it.
            carriedOverTransactions = []
            return
        }

        async let newPeriodTransactions = fetchTransactions(periodID: period.id)
        async let fetchedCategories = fetchCategories()

        carriedOverTransactions = PeriodReviewFiltering.carriedOverTransactions(
            await newPeriodTransactions ?? [],
            previousPeriodID: previousPeriod.id
        )
        categories = await fetchedCategories ?? []
    }

    /// Test seam — injects state directly so pure in-place mutations
    /// (`replaceCarriedOverTransaction`) are testable without a network call.
    func setStateForTesting(carriedOverTransactions: [Wellspent_V1_Transaction] = []) {
        self.carriedOverTransactions = carriedOverTransactions
    }

    private func fetchTransactions(periodID: String) async -> [Wellspent_V1_Transaction]? {
        do {
            let output = try await restClient.listTransactions(.init(query: .init(budgetPeriodId: periodID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load this period's transactions."
                return nil
            }
            return body.transactions.map(BudgetRESTMapping.transaction(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load this period's transactions."
            return nil
        }
    }

    private func fetchCategories() async -> [Wellspent_V1_Category]? {
        guard let output = try? await restClient.listCategories(.init(query: .init(budgetProfileId: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.categories.map(BudgetRESTMapping.category(from:))
    }

    /// Acknowledges the cycle. A no-op on the backend, not an error, if
    /// already confirmed.
    func confirm() async -> Bool {
        errorMessage = nil
        isConfirming = true
        defer { isConfirming = false }
        do {
            let output = try await restClient.confirmPeriodReview(.init(path: .init(id: period.id)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't confirm this period's review."
                Self.logger.error("confirm failed: unexpected response, period=\(self.period.id, privacy: .public)")
                return false
            }
            period = BudgetRESTMapping.period(from: body.period)
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't confirm this period's review."
            Self.logger.error("confirm failed: period=\(self.period.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Re-derives the carried-over rows from the previous period's current
    /// data. Does not dismiss the gate — the user still needs to confirm.
    func retrigger() async {
        errorMessage = nil
        isRetriggering = true
        defer { isRetriggering = false }
        do {
            guard case .ok = try await restClient.retriggerPeriodReview(.init(path: .init(id: period.id))) else {
                errorMessage = "Couldn't recompute this period's carried-over balances."
                Self.logger.error("retrigger failed: unexpected response, period=\(self.period.id, privacy: .public)")
                return
            }
            if let previousPeriod, let refreshed = await fetchTransactions(periodID: period.id) {
                carriedOverTransactions = PeriodReviewFiltering.carriedOverTransactions(refreshed, previousPeriodID: previousPeriod.id)
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't recompute this period's carried-over balances."
            Self.logger.error("retrigger failed: period=\(self.period.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mutates a carried-over row in place after it's edited elsewhere,
    /// mirroring the "mutate in place" pattern used across this codebase.
    func replaceCarriedOverTransaction(_ updated: Wellspent_V1_Transaction) {
        guard let index = carriedOverTransactions.firstIndex(where: { $0.id == updated.id }) else { return }
        carriedOverTransactions[index] = updated
    }
}
