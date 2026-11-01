import SwiftUI
import WellSpentAPI
import WellSpentREST

struct AddEditIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddEditIncomeViewModel
    private let people: [Wellspent_V1_BudgetPerson]
    private let onDone: (Wellspent_V1_IncomeSource) -> Void

    init(
        mode: AddEditIncomeViewModel.Mode,
        budgetProfileID: String,
        countryCode: String,
        currencyCode: String,
        people: [Wellspent_V1_BudgetPerson],
        restClient: WellSpentREST.Client,
        onDone: @escaping (Wellspent_V1_IncomeSource) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddEditIncomeViewModel(
            mode: mode,
            budgetProfileID: budgetProfileID,
            countryCode: countryCode,
            currencyCode: currencyCode,
            restClient: restClient
        ))
        self.people = people
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
            .sheetChrome(isEditing ? Text("Edit Income") : Text("Add Income")) { dismiss() }
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
                            (isEditing ? Text("Save") : Text("Add"))
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("saveIncomeButton")
                }
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("incomeNameField")

            Picker("Type", selection: $viewModel.incomeType) {
                ForEach(IncomeTypeLabel.selectable, id: \.self) { type in
                    Text(IncomeTypeLabel.text(for: type)).tag(type)
                }
            }
            .accessibilityIdentifier("incomeTypePicker")

            AmountTextField(text: $viewModel.amountText)
                .accessibilityIdentifier("incomeAmountField")

            Picker("Frequency", selection: $viewModel.paymentFrequency) {
                ForEach(RecurringTypeLabel.selectable, id: \.self) { frequency in
                    Text(RecurringTypeLabel.text(for: frequency)).tag(frequency)
                }
            }
            .accessibilityIdentifier("incomeFrequencyPicker")

            Toggle("Recurring", isOn: $viewModel.recurring)
                .accessibilityIdentifier("incomeRecurringToggle")

            if viewModel.showBeforeTaxToggle {
                Toggle("Before tax", isOn: $viewModel.beforeTax)
                    .accessibilityIdentifier("incomeBeforeTaxToggle")
            }
        }

        if viewModel.showPayScheduleFields {
            payScheduleSection
        }
    }

    /// Mirrors `AddFixedExpenseView.paymentPlanSection`'s nil-anchor toggle
    /// shape — a pay schedule is optional (irregular income has none).
    @ViewBuilder
    private var payScheduleSection: some View {
        Section {
            Toggle("Has a pay schedule", isOn: Binding(
                get: { viewModel.anchorDate != nil },
                set: { viewModel.anchorDate = $0 ? (viewModel.anchorDate ?? Date()) : nil }
            ))
            .accessibilityIdentifier("incomeHasScheduleToggle")

            if let anchorDate = viewModel.anchorDate {
                DatePicker(
                    "Pay day",
                    selection: Binding(get: { anchorDate }, set: { viewModel.anchorDate = $0 }),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("incomeAnchorDatePicker")

                Stepper(
                    "Counts up to \(viewModel.earlyArrivalToleranceDays) day(s) early",
                    value: $viewModel.earlyArrivalToleranceDays,
                    in: 0...14
                )
                .accessibilityIdentifier("incomeToleranceStepper")
            }
        } header: {
            Text("Pay Schedule")
        } footer: {
            Text("Used to define this budget's periods and to track when this income actually arrives. Leave off for irregular income.")
        }
    }

    @ViewBuilder
    private var attributionSection: some View {
        Section {
            ColorDotPickerField(
                title: "Person",
                selection: $viewModel.personID,
                options: people.map { ColorDotOption(id: $0.id, name: $0.userName, hex: $0.color) },
                noneOption: (id: Int64(0), label: "Unattributed"),
                accessibilityIdentifier: "incomePersonPicker"
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("incomeErrorMessage")
            }
        }
    }
}

#Preview("Add") {
    AddEditIncomeView(
        mode: .add,
        budgetProfileID: "preview-budget",
        countryCode: "US",
        currencyCode: "USD",
        people: [.with { $0.id = 1; $0.userName = "Jane" }],
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}

#Preview("Edit") {
    AddEditIncomeView(
        mode: .edit(.with {
            $0.id = 1
            $0.name = "Paycheck"
            $0.incomeType = .salary
            $0.defaultAmount = .with { $0.units = 2500; $0.currency = "USD" }
            $0.recurring = true
            $0.paymentFrequency = .monthly
        }, schedule: BudgetRESTMapping.IncomeSchedule(anchorDate: nil, earlyArrivalToleranceDays: 0)),
        budgetProfileID: "preview-budget",
        countryCode: "US",
        currencyCode: "USD",
        people: [.with { $0.id = 1; $0.userName = "Jane" }],
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
