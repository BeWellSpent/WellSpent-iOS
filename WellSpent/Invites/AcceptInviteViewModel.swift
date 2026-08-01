import Observation
import WellSpentAPI

@MainActor
@Observable
final class AcceptInviteViewModel {
    private(set) var invite: Wellspent_V1_BudgetInvite?
    private(set) var isLoading = false
    private(set) var isAccepting = false
    private(set) var errorMessage: String?
    private(set) var acceptedBudgetProfileID: String?

    let token: String

    private let publicClient: Wellspent_V1_InviteServiceClient
    /// `nil` when the invite link was opened before the user is
    /// authenticated — `load()` (the public preview) still works either way;
    /// `accept()` requires this to be set.
    private let authenticatedClient: Wellspent_V1_InviteServiceClient?

    init(token: String, publicClient: ProtocolClient, authenticatedClient: ProtocolClient?) {
        self.token = token
        self.publicClient = Wellspent_V1_InviteServiceClient(client: publicClient)
        self.authenticatedClient = authenticatedClient.map { Wellspent_V1_InviteServiceClient(client: $0) }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response = await publicClient.getBudgetInvite(request: .with { $0.token = token })
        switch response.result {
        case .success(let message):
            invite = message.invite
        case .failure(let error):
            errorMessage = error.message ?? "That invite link isn't valid."
        }
    }

    func accept() async {
        // Defensive only — the UI replaces this action with Sign In/Register
        // buttons whenever `authenticatedClient` is nil, so this guard
        // shouldn't be reachable in practice.
        guard let authenticatedClient else { return }

        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }

        let response = await authenticatedClient.acceptBudgetInvite(request: .with { $0.token = token })
        switch response.result {
        case .success(let message):
            acceptedBudgetProfileID = message.budgetProfileID
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't accept that invite."
        }
    }
}
