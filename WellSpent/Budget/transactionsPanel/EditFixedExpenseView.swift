import SwiftUI
import WellSpentAPI

struct EditFixedExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: EditFixedExpenseViewModel
    private let categories: [Wellspent_V1_Category]
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_FixedExpense) -> Void

    init(
        expense: Wellspent_V1_FixedExpense,
        currencyCode: String,
        categories: [Wellspent_V1_Category],
        paymentMethods: [Wellspent_V1_PaymentMethod],
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_FixedExpense) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: EditFixedExpenseViewModel(
            expense: expense,
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
            .navigationTitle("Edit Fixed Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let expense = await viewModel.submit() {
                                onDone(expense)
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
                    .accessibilityIdentifier("saveEditedFixedExpenseButton")
                }
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("editFixedExpenseNameField")

            AmountTextField(text: $viewModel.amountText)
                .accessibilityIdentifier("editFixedExpenseAmountField")
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Start date", selection: $viewModel.startDate, displayedComponents: .date)
                .accessibilityIdentifier("editFixedExpenseStartDatePicker")

            Picker("Repeats", selection: $viewModel.frequencyUnit) {
                Text("Monthly").tag(Wellspent_V1_FrequencyUnit.month)
                Text("Weekly").tag(Wellspent_V1_FrequencyUnit.week)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editFixedExpenseFrequencyPicker")

            if viewModel.frequencyUnit == .week {
                Stepper("Every \(viewModel.intervalWeeks) week(s)", value: $viewModel.intervalWeeks, in: 1...52)
                    .accessibilityIdentifier("editFixedExpenseIntervalWeeksStepper")
            } else {
                Stepper("Every \(viewModel.intervalMonths) month(s)", value: $viewModel.intervalMonths, in: 1...24)
                    .accessibilityIdentifier("editFixedExpenseIntervalMonthsStepper")
            }
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
                accessibilityIdentifier: "editFixedExpenseCategoryPicker"
            )

            ColorDotPickerField(
                title: "Payment Method",
                selection: $viewModel.paymentMethodID,
                options: paymentMethods.map {
                    ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                },
                noneOption: (id: "", label: "None"),
                accessibilityIdentifier: "editFixedExpensePaymentMethodPicker"
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("editFixedExpenseErrorMessage")
            }
        }
    }
}

#Preview {
    EditFixedExpenseView(
        expense: .with {
            $0.id = "fe-1"
            $0.name = "Rent"
            $0.plannedAmount = .with { $0.units = 1500; $0.currency = "USD" }
            $0.dayOfMonth = 1
            $0.frequencyUnit = .month
            $0.intervalMonths = 1
        },
        currencyCode: "USD",
        categories: [.with { $0.id = 1; $0.name = "Housing" }],
        paymentMethods: [.with { $0.id = "pm-1"; $0.name = "Chase Checking" }],
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
