import SwiftUI
import WellSpentAPI

struct AddEditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddEditTransactionViewModel
    private let categories: [Wellspent_V1_Category]
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_Transaction) -> Void

    init(
        mode: AddEditTransactionViewModel.Mode,
        budgetPeriodID: String,
        currencyCode: String,
        categories: [Wellspent_V1_Category],
        paymentMethods: [Wellspent_V1_PaymentMethod],
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_Transaction) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddEditTransactionViewModel(
            mode: mode,
            budgetPeriodID: budgetPeriodID,
            currencyCode: currencyCode,
            authenticatedClient: authenticatedClient
        ))
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.onDone = onDone
    }

    private var isEditing: Bool {
        if case .edit = viewModel.mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                attributionSection
                errorSection
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let transaction = await viewModel.submit() {
                                onDone(transaction)
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
                    .accessibilityIdentifier("saveTransactionButton")
                }
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("transactionNameField")

            Picker("Flow", selection: $viewModel.isReceived) {
                Text("Spent").tag(false)
                Text("Received").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("transactionFlowPicker")

            TextField("Amount", text: $viewModel.amountText)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("transactionAmountField")

            DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                .accessibilityIdentifier("transactionDatePicker")

            Toggle("Recurring", isOn: $viewModel.recurring)
                .accessibilityIdentifier("transactionRecurringToggle")
        }
    }

    @ViewBuilder
    private var attributionSection: some View {
        Section {
            Picker("Category", selection: $viewModel.categoryID) {
                Text("None").tag(Int32(0))
                ForEach(categories, id: \.id) { category in
                    Text(category.name).tag(category.id)
                }
            }
            .accessibilityIdentifier("transactionCategoryPicker")

            Picker("Payment Method", selection: $viewModel.paymentMethodID) {
                Text("Select a payment method").tag("")
                ForEach(paymentMethods, id: \.id) { method in
                    Text(method.alias.isEmpty ? method.name : method.alias).tag(method.id)
                }
            }
            .accessibilityIdentifier("transactionPaymentMethodPicker")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("transactionErrorMessage")
            }
        }
    }
}
