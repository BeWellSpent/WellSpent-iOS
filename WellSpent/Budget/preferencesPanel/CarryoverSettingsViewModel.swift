import Foundation
import Observation
import WellSpentAPI

/// Budget-wide carryover setting.
///
/// Kept separate from `PreferencesViewModel` even though both back the same
/// screen: that one holds the caller's own view preferences and is deliberately
/// not role-gated, while this changes what every member's next period will
/// contain and is Admin only.
@MainActor
@Observable
final class CarryoverSettingsViewModel {
    private(set) var isEnabled = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isAdmin = false
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

        let profileResponse = await client.getBudgetProfile(request: .with { $0.id = budgetProfileID })
        guard case .success(let profileMessage) = profileResponse.result else { return }
        isEnabled = profileMessage.profile.carryoverEnabled

        let peopleResponse = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        guard case .success(let peopleMessage) = peopleResponse.result else { return }
        let role = BudgetRoleResolver.role(
            currentUserID: currentUserID,
            budgetOwnerUserID: profileMessage.profile.userID,
            people: peopleMessage.people
        )
        isAdmin = BudgetRoleResolver.canManageUsers(role)
    }

    func update(enabled: Bool) async {
        // Applied immediately so the switch responds, then rolled back if the
        // server refuses — the UI must never claim a setting that wasn't saved.
        let previous = isEnabled
        isEnabled = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let response = await client.setBudgetCarryoverEnabled(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.enabled = enabled
        })

        if case .failure(let error) = response.result {
            isEnabled = previous
            errorMessage = error.message ?? String(
                localized: "Couldn't save this setting.",
                bundle: AppLanguageStore.currentBundle,
                locale: AppLanguageStore.currentLocale
            )
        }
    }
}
