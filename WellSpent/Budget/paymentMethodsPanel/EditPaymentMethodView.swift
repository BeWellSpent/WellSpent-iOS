import SwiftUI
import WellSpentAPI

struct EditPaymentMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: EditPaymentMethodViewModel
    private let onDone: (Wellspent_V1_PaymentMethod) -> Void

    init(
        method: Wellspent_V1_PaymentMethod,
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_PaymentMethod) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: EditPaymentMethodViewModel(method: method, authenticatedClient: authenticatedClient))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .accessibilityIdentifier("editPaymentMethodNameField")

                    TextField("Alias (optional)", text: $viewModel.alias)
                        .accessibilityIdentifier("editPaymentMethodAliasField")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Color").font(.caption).foregroundStyle(.secondary)
                        PresetColorPickerView(hex: $viewModel.color)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("editPaymentMethodErrorMessage")
                    }
                }
            }
            .sheetChrome(Text("Edit Payment Method")) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let method = await viewModel.submit() {
                                onDone(method)
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
                    .accessibilityIdentifier("saveEditedPaymentMethodButton")
                }
            }
        }
    }
}

#Preview {
    EditPaymentMethodView(
        method: .with {
            $0.id = "preview-pm"
            $0.name = "Chase Visa"
            $0.type = .credit
            $0.alias = "Household Card"
            $0.color = PresetColors.all[2]
        },
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
