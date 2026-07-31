import SwiftUI
import WellSpentAPI

struct AddEditCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddEditCategoryViewModel
    private let onDone: (Wellspent_V1_Category) -> Void

    init(
        mode: AddEditCategoryViewModel.Mode,
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_Category) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddEditCategoryViewModel(mode: mode, authenticatedClient: authenticatedClient))
        self.onDone = onDone
    }

    private var isEditing: Bool {
        if case .edit = viewModel.mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .accessibilityIdentifier("categoryNameField")

                    Picker("Color", selection: $viewModel.color) {
                        Text("None").tag("")
                        ForEach(PresetColors.all, id: \.self) { hex in
                            Text(hex).tag(hex)
                        }
                    }
                    .accessibilityIdentifier("categoryColorPicker")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("categoryErrorMessage")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "Add Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let category = await viewModel.submit() {
                                onDone(category)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text(isEditing ? "Save" : "Add")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("saveCategoryButton")
                }
            }
        }
    }
}
