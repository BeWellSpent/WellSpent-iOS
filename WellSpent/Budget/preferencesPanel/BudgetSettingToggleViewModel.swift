import Foundation
import Observation
import WellSpentAPI

/// Backs `BudgetSettingToggleSection`. The specific field is supplied by the
/// caller as a read/write pair, so one view model serves every budget-wide
/// boolean instead of one per setting.
@MainActor
@Observable
final class BudgetSettingToggleViewModel {
    private(set) var isEnabled = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isAdmin = false
    var errorMessage: String?

    private let budgetProfileID: String
    private let currentUserID: String?
    private let client: Wellspent_V1_BudgetServiceClient
    private let read: (Wellspent_V1_BudgetProfile) -> Bool
    private let write: (Wellspent_V1_BudgetServiceClient, String, Bool) async -> String?

    init(
        budgetProfileID: String,
        currentUserID: String?,
        authenticatedClient: ProtocolClient,
        read: @escaping (Wellspent_V1_BudgetProfile) -> Bool,
        write: @escaping (Wellspent_V1_BudgetServiceClient, String, Bool) async -> String?
    ) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.read = read
        self.write = write
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let profileResponse = await client.getBudgetProfile(request: .with { $0.id = budgetProfileID })
        guard case .success(let profileMessage) = profileResponse.result else { return }
        isEnabled = read(profileMessage.profile)

        let peopleResponse = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        guard case .success(let peopleMessage) = peopleResponse.result else { return }
        isAdmin = BudgetRoleResolver.canManageUsers(
            BudgetRoleResolver.role(
                currentUserID: currentUserID,
                budgetOwnerUserID: profileMessage.profile.userID,
                people: peopleMessage.people
            )
        )
    }

    func update(enabled: Bool) async {
        // Applied immediately so the switch responds, then rolled back if the
        // server refuses — the UI must never claim a setting that wasn't saved.
        let previous = isEnabled
        isEnabled = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        if let failure = await write(client, budgetProfileID, enabled) {
            isEnabled = previous
            errorMessage = failure
        }
    }
}
