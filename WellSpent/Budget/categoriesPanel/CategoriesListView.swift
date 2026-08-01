import SwiftUI
import WellSpentAPI

struct CategoriesListView: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let canEdit: Bool

    @State private var viewModel: CategoriesViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingCategory: Wellspent_V1_Category?
    @State private var deletingCategory: Wellspent_V1_Category?
    @State private var editingSystemCategoryColor: Wellspent_V1_Category?
    @State private var isRandomizing = false

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
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addCategoryButton")
                }
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
                Section {
                    ForEach(viewModel.systemCategories, id: \.id) { category in
                        systemCategoryRow(category, viewModel: viewModel)
                    }
                } header: {
                    HStack {
                        Text("System")
                        Spacer()
                        if canEdit {
                            Button {
                                Task {
                                    isRandomizing = true
                                    await viewModel.randomizeSystemColors()
                                    isRandomizing = false
                                }
                            } label: {
                                if isRandomizing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "shuffle")
                                }
                            }
                            .disabled(isRandomizing || viewModel.systemCategories.isEmpty)
                            .accessibilityIdentifier("randomizeSystemColorsButton")
                        }
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
        .sheet(isPresented: Binding(
            get: { editingSystemCategoryColor != nil },
            set: { if !$0 { editingSystemCategoryColor = nil } }
        )) {
            if let editingSystemCategoryColor {
                SystemCategoryColorSheet(category: editingSystemCategoryColor) { color in
                    Task { await viewModel.updateColor(editingSystemCategoryColor, color: color) }
                }
            }
        }
    }

    private func systemCategoryRow(_ category: Wellspent_V1_Category, viewModel: CategoriesViewModel) -> some View {
        HStack {
            ColorDotView(hex: category.color)
            Text(category.name)
            Spacer()
            if canEdit {
                Button {
                    editingSystemCategoryColor = category
                } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editSystemCategoryColor_\(category.name)")
            }
        }
    }

    private func categoryRow(_ category: Wellspent_V1_Category, viewModel: CategoriesViewModel) -> some View {
        HStack {
            ColorDotView(hex: category.color)
            Text(category.name)
            Spacer()
            if canEdit {
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
}

#Preview {
    NavigationStack {
        CategoriesListView(
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            canEdit: true
        )
    }
}
