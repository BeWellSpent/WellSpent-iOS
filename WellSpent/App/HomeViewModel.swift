import Observation
import WellSpentAPI

/// Stands in for the real budgets-list screen until Phase 2. Loading the
/// authenticated user here proves the authenticated client (token attached,
/// 401 handling wired) actually works end-to-end against the live backend.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var isLoading = false
    private(set) var user: Wellspent_V1_User?
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_UserServiceClient

    init(authenticatedClient: ProtocolClient) {
        self.client = Wellspent_V1_UserServiceClient(client: authenticatedClient)
    }

    func loadMe() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response = await client.getMe(request: Wellspent_V1_GetMeRequest())
        switch response.result {
        case .success(let message):
            user = message.user
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load your profile."
        }
    }
}
