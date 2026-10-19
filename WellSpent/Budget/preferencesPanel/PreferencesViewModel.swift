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
    private let restClient: WellSpentREST.Client

    init(budgetProfileID: String, currentUserID: String?, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let peopleResult = fetchPeople()
        async let user = UserRESTMapping.currentUser(restClient: restClient)

        if let user = await user {
            isFree = user.plan == .free
        }

        guard let people = await peopleResult else { return }

        // An unlinked placeholder has no user to hold preferences against.
        guard let me = ChartPreference.myPerson(currentUserID: currentUserID, people: people) else {
            isLinkedMember = false
            return
        }
        isLinkedMember = true
        planChart = ChartPreference.chartType(for: me.planChartType)
        overviewChart = ChartPreference.chartType(for: me.overviewChartType)
        manualMatchReview = me.manualMatchReviewEnabled
        focusedView = me.focusedViewEnabled
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.people.map(BudgetRESTMapping.person(from:))
    }

    private var savePreferencesFallback: String {
        String(
            localized: "Couldn't save your preferences.",
            bundle: AppLanguageStore.currentBundle,
            locale: AppLanguageStore.currentLocale
        )
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

        do {
            guard case .ok = try await restClient.updateMyBudgetPreferences(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(
                    planChartType: BudgetRESTMapping.restChartType(from: ChartPreference.stored(for: plan)),
                    overviewChartType: BudgetRESTMapping.restChartType(from: ChartPreference.stored(for: overview))
                ))
            )) else {
                planChart = previousPlan
                overviewChart = previousOverview
                errorMessage = savePreferencesFallback
                return
            }
        } catch {
            planChart = previousPlan
            overviewChart = previousOverview
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? savePreferencesFallback
        }
    }

    func updateManualMatchReview(_ enabled: Bool) async {
        let previous = manualMatchReview
        manualMatchReview = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        do {
            guard case .ok = try await restClient.updateMyManualMatchReviewPreference(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(enabled: enabled))
            )) else {
                manualMatchReview = previous
                errorMessage = savePreferencesFallback
                return
            }
        } catch {
            manualMatchReview = previous
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? savePreferencesFallback
        }
    }

    func updateFocusedView(_ enabled: Bool) async {
        let previous = focusedView
        focusedView = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        do {
            guard case .ok = try await restClient.updateMyFocusedViewPreference(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(enabled: enabled))
            )) else {
                focusedView = previous
                errorMessage = savePreferencesFallback
                return
            }
        } catch {
            focusedView = previous
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? savePreferencesFallback
        }
    }
}
