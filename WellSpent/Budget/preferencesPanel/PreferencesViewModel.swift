import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class PreferencesViewModel {
    private(set) var planChart: ExpenseChartView.ChartType = ChartPreference.fallback
    private(set) var overviewChart: ExpenseChartView.ChartType = ChartPreference.fallback
    private(set) var manualMatchReview = true
    private(set) var focusedView = false
    private(set) var isFree = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isLinkedMember = true
    var errorMessage: String?

    private let budgetProfileID: String
    private let currentUserID: String?
    private let client: Wellspent_V1_BudgetServiceClient
    private let userClient: Wellspent_V1_UserServiceClient
    private let restClient: WellSpentREST.Client

    init(budgetProfileID: String, currentUserID: String?, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let user = UserRESTMapping.currentUser(connectClient: userClient, restClient: restClient, useREST: FeatureFlags.csharpUserEnabled)

        if let user = await user {
            isFree = user.plan == .free
        }

        guard case .success(let message) = await peopleResponse.result else { return }

        // An unlinked placeholder has no user to hold preferences against.
        guard let me = ChartPreference.myPerson(currentUserID: currentUserID, people: message.people) else {
            isLinkedMember = false
            return
        }
        isLinkedMember = true
        planChart = ChartPreference.chartType(for: me.planChartType)
        overviewChart = ChartPreference.chartType(for: me.overviewChartType)
        manualMatchReview = me.manualMatchReviewEnabled
        focusedView = me.focusedViewEnabled
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

    func updateManualMatchReview(_ enabled: Bool) async {
        let previous = manualMatchReview
        manualMatchReview = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let response = await client.updateMyManualMatchReviewPreference(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.enabled = enabled
        })

        if case .failure(let error) = response.result {
            manualMatchReview = previous
            errorMessage = error.message ?? String(
                localized: "Couldn't save your preferences.",
                bundle: AppLanguageStore.currentBundle,
                locale: AppLanguageStore.currentLocale
            )
        }
    }

    func updateFocusedView(_ enabled: Bool) async {
        let previous = focusedView
        focusedView = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let response = await client.updateMyFocusedViewPreference(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.enabled = enabled
        })

        if case .failure(let error) = response.result {
            focusedView = previous
            errorMessage = error.message ?? String(
                localized: "Couldn't save your preferences.",
                bundle: AppLanguageStore.currentBundle,
                locale: AppLanguageStore.currentLocale
            )
        }
    }
}
