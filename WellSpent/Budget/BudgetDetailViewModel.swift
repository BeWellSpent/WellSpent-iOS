import Observation
import WellSpentAPI

@MainActor
@Observable
final class BudgetDetailViewModel {
    private(set) var profile: Wellspent_V1_BudgetProfile
    private(set) var isLoading = false
    private(set) var currentPeriod: Wellspent_V1_BudgetPeriod?
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient

    init(profile: Wellspent_V1_BudgetProfile, authenticatedClient: ProtocolClient) {
        self.profile = profile
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func loadPeriod() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = Wellspent_V1_ListBudgetPeriodsRequest.with { $0.budgetProfileID = profile.id }
        let response = await client.listBudgetPeriods(request: request)

        switch response.result {
        case .success(let message):
            // The first non-archived period is the current one; the backend
            // always keeps exactly one active. Fall back to the most recent
            // if every period is somehow archived.
            currentPeriod = message.periods.first(where: { !$0.isArchived }) ?? message.periods.last
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load this budget's period."
        }
    }

    func applyUpdatedProfile(_ updated: Wellspent_V1_BudgetProfile) {
        profile = updated
    }

    func delete() async -> Bool {
        errorMessage = nil
        let request = Wellspent_V1_DeleteBudgetProfileRequest.with { $0.id = profile.id }
        let response = await client.deleteBudgetProfile(request: request)

        switch response.result {
        case .success:
            return true
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that budget."
            return false
        }
    }
}
