import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class PreferencesViewModel {
    private(set) var planChart: ExpenseChartView.ChartType = ChartPreference.fallback
    private(set) var overviewChart: ExpenseChartView.ChartType = ChartPreference.fallback
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isLinkedMember = true
    var errorMessage: String?

    private let budgetProfileID: String
    private let currentUserID: String?
    private let client: Wellspent_V1_BudgetServiceClient

    init(budgetProfileID: String, currentUserID: String?, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let response = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        guard case .success(let message) = response.result else { return }

        // An unlinked placeholder has no user to hold preferences against.
        guard let me = ChartPreference.myPerson(currentUserID: currentUserID, people: message.people) else {
            isLinkedMember = false
            return
        }
        isLinkedMember = true
        planChart = ChartPreference.chartType(for: me.planChartType)
        overviewChart = ChartPreference.chartType(for: me.overviewChartType)
    }

    func update(plan: ExpenseChartView.ChartType, overview: ExpenseChartView.ChartType) async {
        // Applied immediately so the toggle responds, then rolled back if the
        // server refuses — the UI must never claim a preference that wasn't saved.
        let previousPlan = planChart
        let previousOverview = overviewChart
        planChart = plan
        overviewChart = overview

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let response = await client.updateMyBudgetPreferences(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.planChartType = ChartPreference.stored(for: plan)
            $0.overviewChartType = ChartPreference.stored(for: overview)
        })

        if case .failure(let error) = response.result {
            planChart = previousPlan
            overviewChart = previousOverview
            errorMessage = error.message ?? String(
                localized: "Couldn't save your preferences.",
                bundle: AppLanguageStore.currentBundle,
                locale: AppLanguageStore.currentLocale
            )
        }
    }
}
