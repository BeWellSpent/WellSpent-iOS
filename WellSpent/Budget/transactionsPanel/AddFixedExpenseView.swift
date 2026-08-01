import SwiftUI
import WellSpentAPI

struct AddFixedExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddFixedExpenseViewModel
    private let categories: [Wellspent_V1_Category]
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_FixedExpense, Wellspent_V1_Transaction) -> Void

    init(
        budgetProfileID: String,
        currencyCode: String,
        categories: [Wellspent_V1_Category],
        paymentMethods: [Wellspent_V1_PaymentMethod],
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_FixedExpense, Wellspent_V1_Transaction) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddFixedExpenseViewModel(
            budgetProfileID: budgetProfileID,
            currencyCode: currencyCode,
            authenticatedClient: authenticatedClient
        ))
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                attributionSection
                errorSection
            }
            .navigationTitle("Add Fixed Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let result = await viewModel.submit() {
                                onDone(result.expense, result.transaction)
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
                    .accessibilityIdentifier("saveFixedExpenseButton")
                }
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("fixedExpenseNameField")

            AmountTextField(text: $viewModel.amountText)
                .accessibilityIdentifier("fixedExpenseAmountField")
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Start date", selection: $viewModel.startDate, displayedComponents: .date)
                .accessibilityIdentifier("fixedExpenseStartDatePicker")

            Picker("Repeats", selection: $viewModel.frequencyUnit) {
                Text("Monthly").tag(Wellspent_V1_FrequencyUnit.month)
                Text("Weekly").tag(Wellspent_V1_FrequencyUnit.week)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fixedExpenseFrequencyPicker")

            if viewModel.frequencyUnit == .week {
                Stepper("Every \(viewModel.intervalWeeks) week(s)", value: $viewModel.intervalWeeks, in: 1...52)
                    .accessibilityIdentifier("fixedExpenseIntervalWeeksStepper")
            } else {
                Stepper("Every \(viewModel.intervalMonths) month(s)", value: $viewModel.intervalMonths, in: 1...24)
                    .accessibilityIdentifier("fixedExpenseIntervalMonthsStepper")
            }
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
            .accessibilityIdentifier("fixedExpenseCategoryPicker")

            Picker("Payment Method", selection: $viewModel.paymentMethodID) {
                Text("None").tag("")
                ForEach(paymentMethods, id: \.id) { method in
                    Text(method.alias.isEmpty ? method.name : method.alias).tag(method.id)
                }
            }
            .accessibilityIdentifier("fixedExpensePaymentMethodPicker")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("fixedExpenseErrorMessage")
            }
        }
    }
}

#Preview {
    AddFixedExpenseView(
        budgetProfileID: "preview-budget",
        currencyCode: "USD",
        categories: [.with { $0.id = 1; $0.name = "Housing" }],
        paymentMethods: [.with { $0.id = "pm-1"; $0.name = "Chase Checking" }],
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _, _ in }
}
