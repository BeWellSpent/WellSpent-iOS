import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

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
    private let restClient: WellSpentREST.Client
    private let profileID: String

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(profile: Wellspent_V1_BudgetProfile, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.name = profile.name
        self.cycle = profile.cycle
        self.profileID = profile.id
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func submit() async -> Wellspent_V1_BudgetProfile? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let fallback = "Couldn't update that budget."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.updateBudgetProfile(.init(path: .init(id: profileID), body: .json(.init(
                    name: name.trimmingCharacters(in: .whitespaces),
                    cycle: BudgetRESTMapping.restCycle(from: cycle)
                ))))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = fallback
                    return nil
                }
                return BudgetRESTMapping.profile(from: body.profile)
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                return nil
            }
        }

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
            errorMessage = error.message ?? fallback
            return nil
        }
    }
}
