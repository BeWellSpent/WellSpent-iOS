import Observation
import WellSpentAPI

/// Real budgets-list screen, replacing the Phase 1 `HomePlaceholderView`
/// stand-in. Loads the authenticated user (for the verify-email banner and
/// for `currency`/`language`, used to format money in child screens) and the
/// user's budget profiles.
@MainActor
@Observable
final class BudgetListViewModel {
    private(set) var isLoading = false
    private(set) var profiles: [Wellspent_V1_BudgetProfile] = []
    private(set) var currentUser: Wellspent_V1_User?
    private(set) var errorMessage: String?

    let userClient: Wellspent_V1_UserServiceClient
    let budgetClient: Wellspent_V1_BudgetServiceClient

    /// ISO 4217 code. Falls back to "USD" when the profile hasn't loaded yet
    /// or the user hasn't set one — same default the backend uses.
    var currencyCode: String {
        let code = currentUser?.currency ?? ""
        return code.isEmpty ? "USD" : code
    }

    /// BCP 47 locale. Falls back to "en" — same default the backend uses.
    var localeIdentifier: String {
        let language = currentUser?.language ?? ""
        return language.isEmpty ? "en" : language
    }

    init(authenticatedClient: ProtocolClient) {
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.budgetClient = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let meResponse = userClient.getMe(request: Wellspent_V1_GetMeRequest())
        async let profilesResponse = budgetClient.listBudgetProfiles(request: Wellspent_V1_ListBudgetProfilesRequest())

        if case .success(let message) = await meResponse.result {
            currentUser = message.user
        }

        switch await profilesResponse.result {
        case .success(let message):
            profiles = message.profiles
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load your budgets."
        }
    }

    /// Inserts a freshly created profile without a full refetch.
    func addCreatedProfile(_ profile: Wellspent_V1_BudgetProfile) {
        profiles.insert(profile, at: 0)
    }

    /// Replaces an edited profile in place without a full refetch.
    func replaceProfile(_ profile: Wellspent_V1_BudgetProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    /// Applies a `User` returned from `SettingsView`'s `UpdateMe` call
    /// without a full `GetMe` refetch, so `currencyCode`/`localeIdentifier`
    /// (piped into every budget screen) reflect the change immediately.
    func replaceCurrentUser(_ user: Wellspent_V1_User) {
        currentUser = user
    }

    /// Removes a profile that was already deleted elsewhere (e.g. from
    /// `BudgetDetailView`'s own delete action) — does not issue another
    /// `DeleteBudgetProfile` call.
    func removeProfile(id: String) {
        profiles.removeAll { $0.id == id }
    }

    func delete(_ profile: Wellspent_V1_BudgetProfile) async {
        errorMessage = nil
        let request = Wellspent_V1_DeleteBudgetProfileRequest.with { $0.id = profile.id }
        let response = await budgetClient.deleteBudgetProfile(request: request)

        switch response.result {
        case .success:
            profiles.removeAll { $0.id == profile.id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that budget."
        }
    }
}
