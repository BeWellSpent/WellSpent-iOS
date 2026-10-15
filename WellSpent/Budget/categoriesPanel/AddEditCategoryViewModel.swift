import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AddEditCategoryViewModel {
    enum Mode {
        case add
        case edit(Wellspent_V1_Category)
    }

    var name: String
    var color: String

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let mode: Mode

    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(mode: Mode, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.mode = mode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient

        switch mode {
        case .add:
            name = ""
            color = ""
        case .edit(let category):
            name = category.name
            color = category.color
        }
    }

    func submit() async -> Wellspent_V1_Category? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let fallback = "Couldn't create that category."
            if FeatureFlags.csharpBudgetEnabled {
                do {
                    let output = try await restClient.createCategory(.init(body: .json(.init(name: trimmedName, color: color))))
                    guard case .ok(let ok) = output, let body = try? ok.body.json else {
                        errorMessage = fallback
                        return nil
                    }
                    return BudgetRESTMapping.category(from: body.category)
                } catch {
                    errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                    return nil
                }
            }

            let request = Wellspent_V1_CreateCategoryRequest.with {
                $0.name = trimmedName
                $0.color = color
            }
            let response = await client.createCategory(request: request)
            switch response.result {
            case .success(let message):
                return message.category
            case .failure(let error):
                errorMessage = error.message ?? fallback
                return nil
            }
        case .edit(let existing):
            let fallback = "Couldn't update that category."
            if FeatureFlags.csharpBudgetEnabled {
                do {
                    let output = try await restClient.updateCategory(.init(
                        path: .init(id: existing.id),
                        body: .json(.init(name: trimmedName, color: color))
                    ))
                    guard case .ok(let ok) = output, let body = try? ok.body.json else {
                        errorMessage = fallback
                        return nil
                    }
                    return BudgetRESTMapping.category(from: body.category)
                } catch {
                    errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                    return nil
                }
            }

            let request = Wellspent_V1_UpdateCategoryRequest.with {
                $0.id = existing.id
                $0.name = trimmedName
                $0.color = color
            }
            let response = await client.updateCategory(request: request)
            switch response.result {
            case .success(let message):
                return message.category
            case .failure(let error):
                errorMessage = error.message ?? fallback
                return nil
            }
        }
    }
}
