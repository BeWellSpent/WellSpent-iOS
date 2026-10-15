import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class CreateBudgetViewModel {
    var name = ""
    var cycle: Wellspent_V1_BudgetCycle = .monthly
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func submit() async -> Wellspent_V1_BudgetProfile? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        if FeatureFlags.csharpBudgetEnabled {
            return await submitViaREST()
        }

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

    private func submitViaREST() async -> Wellspent_V1_BudgetProfile? {
        let fallback = "Couldn't create that budget."
        do {
            let output = try await restClient.createBudgetProfile(.init(body: .json(.init(
                name: name.trimmingCharacters(in: .whitespaces),
                cycle: BudgetRESTMapping.restCycle(from: cycle)
            ))))
            switch output {
            case .ok(let ok):
                guard let body = try? ok.body.json else { errorMessage = fallback; return nil }
                return BudgetRESTMapping.profile(from: body.profile)
            case .badRequest(let badRequest):
                errorMessage = (try? badRequest.body.json.message) ?? fallback
                return nil
            default:
                errorMessage = fallback
                return nil
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return nil
        }
    }

    static func errorMessage(for error: ConnectError) -> String {
        error.message ?? "Couldn't create that budget."
    }
}
