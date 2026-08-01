import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class CreateBudgetViewModel {
    var name = ""
    var cycle: Wellspent_V1_BudgetCycle = .monthly
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(authenticatedClient: ProtocolClient) {
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func submit() async -> Wellspent_V1_BudgetProfile? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_CreateBudgetProfileRequest.with {
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.cycle = cycle
        }
        let response = await client.createBudgetProfile(request: request)

        switch response.result {
        case .success(let message):
            return message.profile
        case .failure(let error):
            errorMessage = Self.errorMessage(for: error)
            return nil
        }
    }

    static func errorMessage(for error: ConnectError) -> String {
        error.message ?? "Couldn't create that budget."
    }
}
