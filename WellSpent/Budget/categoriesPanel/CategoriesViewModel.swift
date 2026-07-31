import Observation
import WellSpentAPI

@MainActor
@Observable
final class CategoriesViewModel {
    private(set) var isLoading = false
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient

    var systemCategories: [Wellspent_V1_Category] {
        categories.filter(\.isSystem).sorted { $0.name < $1.name }
    }

    var userCategories: [Wellspent_V1_Category] {
        categories.filter { !$0.isSystem }.sorted { $0.name < $1.name }
    }

    init(budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = Wellspent_V1_ListCategoriesRequest.with { $0.budgetProfileID = budgetProfileID }
        let response = await client.listCategories(request: request)

        switch response.result {
        case .success(let message):
            categories = message.categories
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load categories."
        }
    }

    func addCategory(_ category: Wellspent_V1_Category) {
        categories.append(category)
    }

    func replaceCategory(_ category: Wellspent_V1_Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
    }

    @discardableResult
    func delete(id: Int32, replacementID: Int32) async -> Bool {
        errorMessage = nil
        let request = Wellspent_V1_DeleteCategoryRequest.with {
            $0.id = id
            $0.replacementID = replacementID
        }
        let response = await client.deleteCategory(request: request)

        switch response.result {
        case .success:
            categories.removeAll { $0.id == id }
            return true
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that category."
            return false
        }
    }
}
