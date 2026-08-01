import Foundation
import Observation
import WellSpentAPI

/// Kept separate from `CreateBudgetViewModel` — edit starts pre-populated
/// from an existing profile and submits `UpdateBudgetProfile`, not `Create`;
/// sharing one view model would mean branching submit behavior on a flag.
@MainActor
@Observable
final class EditBudgetViewModel {
    var name: String
    var cycle: Wellspent_V1_BudgetCycle
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient
    private let profileID: String

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(profile: Wellspent_V1_BudgetProfile, authenticatedClient: ProtocolClient) {
        self.name = profile.name
        self.cycle = profile.cycle
        self.profileID = profile.id
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func submit() async -> Wellspent_V1_BudgetProfile? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_UpdateBudgetProfileRequest.with {
            $0.id = profileID
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.cycle = cycle
        }
        let response = await client.updateBudgetProfile(request: request)

        switch response.result {
        case .success(let message):
            return message.profile
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that budget."
            return nil
        }
    }
}
