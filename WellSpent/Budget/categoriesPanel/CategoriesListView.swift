import SwiftUI
import WellSpentAPI

struct CategoriesListView: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient

    @State private var viewModel: CategoriesViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingCategory: Wellspent_V1_Category?
    @State private var deletingCategory: Wellspent_V1_Category?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addCategoryButton")
            }
        }
        .task {
            if viewModel == nil {
                viewModel = CategoriesViewModel(budgetProfileID: budgetProfileID, authenticatedClient: authenticatedClient)
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: CategoriesViewModel) -> some View {
        List {
            if viewModel.categories.isEmpty && viewModel.isLoading {
                ProgressView()
            } else {
                Section("System") {
                    ForEach(viewModel.systemCategories, id: \.id) { category in
                        Text(category.name)
                    }
                }

                Section("Your Categories") {
                    if viewModel.userCategories.isEmpty {
                        Text("No categories yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.userCategories, id: \.id) { category in
                            categoryRow(category, viewModel: viewModel)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddEditCategoryView(mode: .add, authenticatedClient: authenticatedClient) { category in
                viewModel.addCategory(category)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            if let editingCategory {
                AddEditCategoryView(mode: .edit(editingCategory), authenticatedClient: authenticatedClient) { updated in
                    viewModel.replaceCategory(updated)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { deletingCategory != nil },
            set: { if !$0 { deletingCategory = nil } }
        )) {
            if let deletingCategory {
                DeleteCategoryView(
                    category: deletingCategory,
                    otherCategories: viewModel.categories.filter { $0.id != deletingCategory.id }
                ) { replacementID in
                    Task { await viewModel.delete(id: deletingCategory.id, replacementID: replacementID) }
                }
            }
        }
    }

    private func categoryRow(_ category: Wellspent_V1_Category, viewModel: CategoriesViewModel) -> some View {
        HStack {
            Text(category.name)
            Spacer()
            Button {
                editingCategory = category
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editCategory_\(category.name)")

            Button {
                deletingCategory = category
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deleteCategory_\(category.name)")
        }
    }
}

#Preview {
    NavigationStack {
        CategoriesListView(
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }
}
