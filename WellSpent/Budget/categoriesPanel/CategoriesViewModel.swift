import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class CategoriesViewModel {
    private(set) var isLoading = false
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let restClient: WellSpentREST.Client

    /// Sorted by the *displayed* name: the server orders by the English
    /// name, which stops being the reader's order once system categories are
    /// translated.
    var systemCategories: [Wellspent_V1_Category] {
        SystemCategoryNames.sorted(categories.filter(\.isSystem))
    }

    var userCategories: [Wellspent_V1_Category] {
        SystemCategoryNames.sorted(categories.filter { !$0.isSystem })
    }

    init(budgetProfileID: String, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let output = try await restClient.listCategories(.init(query: .init(budgetProfileId: budgetProfileID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load categories."
                return
            }
            categories = body.categories.map(BudgetRESTMapping.category(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load categories."
        }
    }

    func addCategory(_ category: Wellspent_V1_Category) {
        categories.append(category)
    }

    func replaceCategory(_ category: Wellspent_V1_Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
    }

    /// Color-only update — used by the system-category color editor, where
    /// name/deletion aren't editable but color still is (each user can
    /// color-code the shared global categories for their own view).
    func updateColor(_ category: Wellspent_V1_Category, color: String) async {
        errorMessage = nil
        let fallback = "Couldn't update that category's color."
        do {
            let output = try await restClient.updateCategory(.init(
                path: .init(id: category.id),
                body: .json(.init(name: category.name, color: color))
            ))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                return
            }
            replaceCategory(BudgetRESTMapping.category(from: body.category))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
        }
    }

    /// Mirrors web's `handleRandomizeSystemColors` — assigns each system
    /// category an evenly-spaced distinct color in one action.
    func randomizeSystemColors() async {
        let colors = DistinctColorGenerator.generate(count: systemCategories.count)
        for (category, color) in zip(systemCategories, colors) {
            await updateColor(category, color: color)
        }
    }

    @discardableResult
    func delete(id: Int32, replacementID: Int32) async -> Bool {
        errorMessage = nil
        let fallback = "Couldn't delete that category."
        do {
            guard case .ok = try await restClient.deleteCategory(.init(path: .init(id: id), query: .init(replacementId: replacementID))) else {
                errorMessage = fallback
                return false
            }
            categories.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }
}
