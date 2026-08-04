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
                paymentPlanSection
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
            DatePicker("Start date", selection: Binding(get: { viewModel.startDate }, set: viewModel.setStartDate), displayedComponents: .date)
                .accessibilityIdentifier("fixedExpenseStartDatePicker")

            Picker("Repeats", selection: Binding(get: { viewModel.frequencyUnit }, set: viewModel.setFrequencyUnit)) {
                Text("Monthly").tag(Wellspent_V1_FrequencyUnit.month)
                Text("Weekly").tag(Wellspent_V1_FrequencyUnit.week)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fixedExpenseFrequencyPicker")

            if viewModel.frequencyUnit == .week {
                Stepper("Every \(viewModel.intervalWeeks) week(s)", value: Binding(get: { viewModel.intervalWeeks }, set: viewModel.setIntervalWeeks), in: 1...52)
                    .accessibilityIdentifier("fixedExpenseIntervalWeeksStepper")
            } else {
                Stepper("Every \(viewModel.intervalMonths) month(s)", value: Binding(get: { viewModel.intervalMonths }, set: viewModel.setIntervalMonths), in: 1...24)
                    .accessibilityIdentifier("fixedExpenseIntervalMonthsStepper")
            }
        }
    }

    @ViewBuilder
    private var paymentPlanSection: some View {
        Section {
            TextField("Number of payments", text: Binding(get: { viewModel.paymentsText }, set: viewModel.handlePaymentsTextChange))
                .keyboardType(.numberPad)
                .accessibilityIdentifier("fixedExpensePaymentsField")

            Toggle("Has end date", isOn: Binding(
                get: { viewModel.endDate != nil },
                set: { viewModel.handleEndDateChange($0 ? (viewModel.endDate ?? viewModel.startDate) : nil) }
            ))
            .accessibilityIdentifier("fixedExpenseHasEndDateToggle")

            if viewModel.endDate != nil {
                DatePicker(
                    "End date",
                    selection: Binding(get: { viewModel.endDate ?? viewModel.startDate }, set: { viewModel.handleEndDateChange($0) }),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("fixedExpenseEndDatePicker")
            }
        } header: {
            Text("Payment plan (optional)")
        } footer: {
            Text("Leave blank for an expense that repeats indefinitely.")
        }
    }

    @ViewBuilder
    private var attributionSection: some View {
        Section {
            ColorDotPickerField(
                title: "Category",
                selection: $viewModel.categoryID,
                options: categories.map { ColorDotOption(id: $0.id, name: $0.name, hex: $0.color) },
                noneOption: (id: Int32(0), label: "None"),
                accessibilityIdentifier: "fixedExpenseCategoryPicker"
            )

            ColorDotPickerField(
                title: "Payment Method",
                selection: $viewModel.paymentMethodID,
                options: paymentMethods.map {
                    ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                },
                noneOption: (id: "", label: "None"),
                accessibilityIdentifier: "fixedExpensePaymentMethodPicker"
            )
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
