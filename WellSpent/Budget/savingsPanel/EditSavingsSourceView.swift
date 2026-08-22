import SwiftUI
import WellSpentAPI

struct EditSavingsSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: EditSavingsSourceViewModel
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_SavingsSource) -> Void

    init(
        source: Wellspent_V1_SavingsSource,
        currencyCode: String,
        periodStartDate: Date?,
        paymentMethods: [Wellspent_V1_PaymentMethod],
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_SavingsSource) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: EditSavingsSourceViewModel(
            source: source,
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
                        .accessibilityIdentifier("editSavingsNameField")

                    AmountTextField(text: $viewModel.amountText)
                        .accessibilityIdentifier("editSavingsAmountField")

                    ColorDotPickerField(
                        title: "Payment Method",
                        selection: $viewModel.paymentMethodID,
                        options: paymentMethods.map {
                            ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                        },
                        noneOption: (id: "", label: "No payment method"),
                        accessibilityIdentifier: "editSavingsPaymentMethodPicker"
                    )
                }

                Section {
                    SavingsPaymentDaysGrid(selectedDays: $viewModel.paymentDays, daysInMonth: viewModel.daysInMonth)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("editSavingsErrorMessage")
                    }
                }
            }
            .sheetChrome(Text("Edit Savings")) { dismiss() }
            .toolbar {
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
                            Text("Save")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("saveEditedSavingsButton")
                }
            }
        }
    }
}

#Preview {
    EditSavingsSourceView(
        source: .with {
            $0.id = 1
            $0.name = "Emergency Fund"
            $0.amount = .with { $0.units = 300; $0.currency = "USD" }
            $0.paymentDays = [1]
        },
        currencyCode: "USD",
        periodStartDate: nil,
        paymentMethods: [.with { $0.id = "pm-1"; $0.name = "Chase Checking" }],
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
