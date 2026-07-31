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

                    Picker("Owner", selection: $viewModel.personID) {
                        Text("Select a person").tag(Int64(0))
                        ForEach(people, id: \.id) { person in
                            Text(person.userName).tag(person.id)
                        }
                    }
                    .accessibilityIdentifier("paymentMethodOwnerPicker")

                    Picker("Color", selection: $viewModel.color) {
                        Text("None").tag("")
                        ForEach(PresetColors.all, id: \.self) { hex in
                            Text(hex).tag(hex)
                        }
                    }
                    .accessibilityIdentifier("paymentMethodColorPicker")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("paymentMethodErrorMessage")
                    }
                }
            }
            .navigationTitle("Add Payment Method")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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
