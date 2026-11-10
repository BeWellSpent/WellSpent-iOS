import Foundation
import os
import WellSpentAPI
import WellSpentREST

/// Writes the person's chart preferences for a budget — both values at once,
/// since the endpoint replaces both. Shared by Home's and Plan's chart menus.
@MainActor
enum ChartPreferenceSaver {
    private static let logger = AppLogger.logger("ChartPreference")

    static func save(
        plan: Wellspent_V1_ChartType,
        overview: Wellspent_V1_ChartType,
        budgetProfileID: String,
        restClient: WellSpentREST.Client
    ) async -> Bool {
        do {
            let output = try await restClient.updateMyBudgetPreferences(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(
                    planChartType: BudgetRESTMapping.restChartType(from: plan),
                    overviewChartType: BudgetRESTMapping.restChartType(from: overview)
                ))
            ))
            guard case .ok = output else {
                RESTNetworkError.logUnexpectedOutput(output)
                return false
            }
            return true
        } catch {
            _ = RESTNetworkError.connectivityMessage(for: error)
            logger.error("chart preference save failed budgetProfileId=\(budgetProfileID, privacy: .public)")
            return false
        }
    }
}
