import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

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
    private let restClient: WellSpentREST.Client
    private let read: (Wellspent_V1_BudgetProfile) -> Bool
    /// Deliberately takes no client — each setting's write closure is
    /// self-contained and branches its own transport, decoupled from
    /// whichever client type this view model happens to use for its own
    /// reads (mirrors web's identical `BudgetSettingToggle.tsx` decoupling).
    private let write: (String, Bool) async -> String?

    init(
        budgetProfileID: String,
        currentUserID: String?,
        authenticatedClient: ProtocolClient,
        restClient: WellSpentREST.Client,
        read: @escaping (Wellspent_V1_BudgetProfile) -> Bool,
        write: @escaping (String, Bool) async -> String?
    ) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
        self.read = read
        self.write = write
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let profile = await fetchProfile() else { return }
        isEnabled = read(profile)

        guard let people = await fetchPeople() else { return }
        isAdmin = BudgetRoleResolver.canManageUsers(
            BudgetRoleResolver.role(
                currentUserID: currentUserID,
                budgetOwnerUserID: profile.userID,
                people: people
            )
        )
    }

    private func fetchProfile() async -> Wellspent_V1_BudgetProfile? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.getBudgetProfile(.init(path: .init(id: budgetProfileID))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return BudgetRESTMapping.profile(from: body.profile)
        }
        let response = await client.getBudgetProfile(request: .with { $0.id = budgetProfileID })
        guard case .success(let message) = response.result else { return nil }
        return message.profile
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return body.people.map(BudgetRESTMapping.person(from:))
        }
        guard case .success(let message) = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID }).result else {
            return nil
        }
        return message.people
    }

    func update(enabled: Bool) async {
        // Applied immediately so the switch responds, then rolled back if the
        // server refuses — the UI must never claim a setting that wasn't saved.
        let previous = isEnabled
        isEnabled = enabled

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        if let failure = await write(budgetProfileID, enabled) {
            isEnabled = previous
            errorMessage = failure
        }
    }
}
