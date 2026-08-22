import SwiftUI
import WellSpentAPI

struct AddPaymentMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddPaymentMethodViewModel
    private let people: [Wellspent_V1_BudgetPerson]
    private let onDone: (Wellspent_V1_PaymentMethod) -> Void

    init(
        people: [Wellspent_V1_BudgetPerson],
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_PaymentMethod) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddPaymentMethodViewModel(authenticatedClient: authenticatedClient))
        self.people = people
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .accessibilityIdentifier("paymentMethodNameField")

                    Picker("Type", selection: $viewModel.type) {
                        ForEach(PaymentTypeLabel.selectable, id: \.self) { type in
                            Text(PaymentTypeLabel.text(for: type)).tag(type)
                        }
                    }
                    .accessibilityIdentifier("paymentMethodTypePicker")

                    ColorDotPickerField(
                        title: "Owner",
                        selection: $viewModel.personID,
                        options: people.map { ColorDotOption(id: $0.id, name: $0.userName, hex: $0.color) },
                        noneOption: (id: Int64(0), label: "Select a person"),
                        accessibilityIdentifier: "paymentMethodOwnerPicker"
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Color").font(.caption).foregroundStyle(.secondary)
                        PresetColorPickerView(hex: $viewModel.color)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("paymentMethodErrorMessage")
                    }
                }
            }
            .sheetChrome(Text("Add Payment Method")) { dismiss() }
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
                            Text("Add")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("savePaymentMethodButton")
                }
            }
        }
    }
}

#Preview {
    AddPaymentMethodView(
        people: [.with { $0.id = 1; $0.userName = "Jane" }],
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
