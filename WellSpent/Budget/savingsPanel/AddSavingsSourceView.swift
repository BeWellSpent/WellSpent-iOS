import SwiftUI
import WellSpentAPI

struct AddSavingsSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddSavingsSourceViewModel
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_SavingsSource) -> Void

    init(
        budgetProfileID: String,
        currencyCode: String,
        periodStartDate: Date?,
        paymentMethods: [Wellspent_V1_PaymentMethod],
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_SavingsSource) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddSavingsSourceViewModel(
            budgetProfileID: budgetProfileID,
            currencyCode: currencyCode,
            periodStartDate: periodStartDate,
            authenticatedClient: authenticatedClient
        ))
        self.paymentMethods = paymentMethods
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .accessibilityIdentifier("addSavingsNameField")

                    AmountTextField(text: $viewModel.amountText)
                        .accessibilityIdentifier("addSavingsAmountField")

                    ColorDotPickerField(
                        title: "Payment Method",
                        selection: $viewModel.paymentMethodID,
                        options: paymentMethods.map {
                            ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                        },
                        noneOption: (id: "", label: "None"),
                        accessibilityIdentifier: "addSavingsPaymentMethodPicker"
                    )
                }

                Section {
                    SavingsPaymentDaysGrid(selectedDays: $viewModel.paymentDays, daysInMonth: viewModel.daysInMonth)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("addSavingsErrorMessage")
                    }
                }
            }
            .navigationTitle("Add Savings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let source = await viewModel.submit() {
                                onDone(source)
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
                    .accessibilityIdentifier("saveSavingsButton")
                }
            }
        }
    }
}

#Preview {
    AddSavingsSourceView(
        budgetProfileID: "preview-budget",
        currencyCode: "USD",
        periodStartDate: nil,
        paymentMethods: [.with { $0.id = "pm-1"; $0.name = "Chase Checking" }],
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
