import SwiftUI
import WellSpentAPI

struct EditBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: EditBudgetViewModel
    private let onSaved: (Wellspent_V1_BudgetProfile) -> Void

    init(profile: Wellspent_V1_BudgetProfile, authenticatedClient: ProtocolClient, onSaved: @escaping (Wellspent_V1_BudgetProfile) -> Void) {
        _viewModel = Bindable(wrappedValue: EditBudgetViewModel(profile: profile, authenticatedClient: authenticatedClient))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Budget name", text: $viewModel.name)
                        .accessibilityIdentifier("editBudgetNameField")

                    Picker("Cycle", selection: $viewModel.cycle) {
                        ForEach(BudgetCycleLabel.selectable, id: \.self) { cycle in
                            Text(BudgetCycleLabel.text(for: cycle)).tag(cycle)
                        }
                    }
                    .accessibilityIdentifier("editBudgetCyclePicker")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("editBudgetErrorMessage")
                    }
                }
            }
            .navigationTitle("Edit Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let profile = await viewModel.submit() {
                                onSaved(profile)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("saveBudgetButton")
                }
            }
        }
    }
}
