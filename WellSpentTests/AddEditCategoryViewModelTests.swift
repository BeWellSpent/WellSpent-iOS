import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddEditCategoryViewModel")
@MainActor
struct AddEditCategoryViewModelTests {
    private func makeViewModel(mode: AddEditCategoryViewModel.Mode = .add) -> AddEditCategoryViewModel {
        AddEditCategoryViewModel(mode: mode, authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    @Test("submit is disabled until a non-blank name is present")
    func canSubmitReflectsName() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "   "
        #expect(!viewModel.canSubmit)

        viewModel.name = "Groceries"
        #expect(viewModel.canSubmit)
    }

    @Test("editing an existing category pre-fills its fields")
    func editModePrefill() {
        let category = Wellspent_V1_Category.with {
            $0.id = 7
            $0.name = "Groceries"
            $0.color = "#26A69A"
            $0.isSystem = false
        }
        let viewModel = makeViewModel(mode: .edit(category))

        #expect(viewModel.name == "Groceries")
        #expect(viewModel.color == "#26A69A")
    }
}
