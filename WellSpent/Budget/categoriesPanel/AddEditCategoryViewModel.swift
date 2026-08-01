import Foundation
import Observation
import WellSpentAPI

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

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(mode: Mode, authenticatedClient: ProtocolClient) {
        self.mode = mode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)

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
            let request = Wellspent_V1_CreateCategoryRequest.with {
                $0.name = trimmedName
                $0.color = color
            }
            let response = await client.createCategory(request: request)
            switch response.result {
            case .success(let message):
                return message.category
            case .failure(let error):
                errorMessage = error.message ?? "Couldn't create that category."
                return nil
            }
        case .edit(let existing):
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
                errorMessage = error.message ?? "Couldn't update that category."
                return nil
            }
        }
    }
}
