import SwiftUI
import WellSpentAPI

struct CreateBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: CreateBudgetViewModel
    private let onCreated: (Wellspent_V1_BudgetProfile) -> Void

    init(authenticatedClient: ProtocolClient, onCreated: @escaping (Wellspent_V1_BudgetProfile) -> Void) {
        _viewModel = Bindable(wrappedValue: CreateBudgetViewModel(authenticatedClient: authenticatedClient))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Budget name", text: $viewModel.name)
                        .accessibilityIdentifier("budgetNameField")

                    Picker("Cycle", selection: $viewModel.cycle) {
                        ForEach(BudgetCycleLabel.selectable, id: \.self) { cycle in
                            Text(BudgetCycleLabel.text(for: cycle)).tag(cycle)
                        }
                    }
                    .accessibilityIdentifier("budgetCyclePicker")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("createBudgetErrorMessage")
                    }
                }
            }
            .navigationTitle("New Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let profile = await viewModel.submit() {
                                onCreated(profile)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("createBudgetButton")
                }
            }
        }
    }
}

#Preview {
    CreateBudgetSheet(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")) { _ in }
}
