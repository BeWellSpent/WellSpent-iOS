import SwiftUI
import WellSpentAPI
import WellSpentREST

struct EditFixedExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: EditFixedExpenseViewModel
    private let categories: [Wellspent_V1_Category]
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_FixedExpense) -> Void
    /// Only this fixed expense's own id/budget/remaining balance are needed
    /// to open the "Pay in full" sheet — threaded separately from `expense`
    /// since `remainingBalance` has no proto equivalent (see
    /// `BudgetRESTMapping.FixedExpensePayoffInfo`).
    private let fixedExpenseID: String
    private let budgetProfileID: String
    private let currencyCode: String
    private let remainingBalance: Wellspent_V1_Money
    private let hasPaymentPlan: Bool
    private let restClient: WellSpentREST.Client
    @State private var isPayInFullPresented = false

    init(
        expense: Wellspent_V1_FixedExpense,
        currencyCode: String,
        categories: [Wellspent_V1_Category],
        paymentMethods: [Wellspent_V1_PaymentMethod],
        remainingBalance: Wellspent_V1_Money = Wellspent_V1_Money(),
        restClient: WellSpentREST.Client,
        onDone: @escaping (Wellspent_V1_FixedExpense) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: EditFixedExpenseViewModel(
            expense: expense,
            currencyCode: currencyCode,
            restClient: restClient
        ))
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.onDone = onDone
        self.fixedExpenseID = expense.id
        self.budgetProfileID = expense.budgetProfileID
        self.currencyCode = currencyCode
        self.remainingBalance = remainingBalance
        self.hasPaymentPlan = expense.totalPayments > 0
        self.restClient = restClient
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                paymentPlanSection
                payInFullSection
                attributionSection
                errorSection
            }
            .sheetChrome(Text("Edit Fixed Expense")) { dismiss() }
            .toolbar {
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
        .sheet(isPresented: $isPayInFullPresented) {
            PayFixedExpenseInFullView(
                budgetProfileID: budgetProfileID,
                fixedExpenseID: fixedExpenseID,
                currencyCode: currencyCode,
                remainingBalance: remainingBalance,
                restClient: restClient
            ) { _, fixedExpense in
                onDone(fixedExpense)
                dismiss()
            }
        }
    }

    /// Settles the plan's remaining balance in one payment — any fixed
    /// expense with a payment plan, not only installment plans.
    @ViewBuilder
    private var payInFullSection: some View {
        if hasPaymentPlan {
            Section {
                Button("Pay in Full") {
                    isPayInFullPresented = true
                }
                .accessibilityIdentifier("payInFullButton")
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            AmountHeroField(
                text: $viewModel.amountText,
                accessibilityIdentifier: "editFixedExpenseAmountField"
            )

            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("editFixedExpenseNameField")
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Start date", selection: Binding(get: { viewModel.startDate }, set: viewModel.setStartDate), displayedComponents: .date)
                .accessibilityIdentifier("editFixedExpenseStartDatePicker")

            Picker("Repeats", selection: Binding(get: { viewModel.frequencyUnit }, set: viewModel.setFrequencyUnit)) {
                Text("Monthly").tag(Wellspent_V1_FrequencyUnit.month)
                Text("Weekly").tag(Wellspent_V1_FrequencyUnit.week)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editFixedExpenseFrequencyPicker")

            if viewModel.frequencyUnit == .week {
                Stepper("Every \(viewModel.intervalWeeks) week(s)", value: Binding(get: { viewModel.intervalWeeks }, set: viewModel.setIntervalWeeks), in: 1...52)
                    .accessibilityIdentifier("editFixedExpenseIntervalWeeksStepper")
            } else {
                Stepper("Every \(viewModel.intervalMonths) month(s)", value: Binding(get: { viewModel.intervalMonths }, set: viewModel.setIntervalMonths), in: 1...24)
                    .accessibilityIdentifier("editFixedExpenseIntervalMonthsStepper")
            }
        }
    }

    @ViewBuilder
    private var paymentPlanSection: some View {
        Section {
            TextField("Number of payments", text: Binding(get: { viewModel.paymentsText }, set: viewModel.handlePaymentsTextChange))
                .keyboardType(.numberPad)
                .accessibilityIdentifier("editFixedExpensePaymentsField")

            Toggle("Has end date", isOn: Binding(
                get: { viewModel.endDate != nil },
                set: { viewModel.handleEndDateChange($0 ? (viewModel.endDate ?? viewModel.startDate) : nil) }
            ))
            .accessibilityIdentifier("editFixedExpenseHasEndDateToggle")

            if viewModel.endDate != nil {
                DatePicker(
                    "End date",
                    selection: Binding(get: { viewModel.endDate ?? viewModel.startDate }, set: { viewModel.handleEndDateChange($0) }),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("editFixedExpenseEndDatePicker")
            }
        } header: {
            Text("Payment plan (optional)")
        } footer: {
            if let paymentsMadeText = viewModel.paymentsMadeText {
                Text(paymentsMadeText)
                    .accessibilityIdentifier("editFixedExpensePaymentsMadeText")
            } else {
                Text("Leave blank for an expense that repeats indefinitely.")
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
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
