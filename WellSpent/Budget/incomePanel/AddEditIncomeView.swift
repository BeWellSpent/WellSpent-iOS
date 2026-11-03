import SwiftUI
import WellSpentAPI
import WellSpentREST

struct AddEditIncomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddEditIncomeViewModel
    private let people: [Wellspent_V1_BudgetPerson]
    /// Called after every submit attempt, success or partial failure — the
    /// list reloads either way so it reflects whatever actually landed
    /// server-side rather than trusting optimistic local state.
    private let onDone: () -> Void

    init(
        mode: AddEditIncomeViewModel.Mode,
        budgetProfileID: String,
        countryCode: String,
        currencyCode: String,
        people: [Wellspent_V1_BudgetPerson],
        restClient: WellSpentREST.Client,
        onDone: @escaping () -> Void
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
                            let success = await viewModel.submit()
                            onDone()
                            if success { dismiss() }
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
    /// shape — a pay schedule is optional (irregular income has none). When
    /// on, 1-4 paydays can be added; the amount field above is this job's
    /// whole-period total, split evenly across them (`splitAmountText`).
    @ViewBuilder
    private var payScheduleSection: some View {
        Section {
            Toggle("Has a pay schedule", isOn: Binding(
                get: { viewModel.hasPaySchedule },
                set: { viewModel.setHasPaySchedule($0) }
            ))
            .accessibilityIdentifier("incomeHasScheduleToggle")

            if viewModel.hasPaySchedule {
                Stepper(
                    "Paid \(viewModel.payDateCount) time(s) per period",
                    onIncrement: { viewModel.setPayDateCount(viewModel.payDateCount + 1) },
                    onDecrement: { viewModel.setPayDateCount(viewModel.payDateCount - 1) }
                )
                .accessibilityIdentifier("incomePayDateCountStepper")

                ForEach(Array(viewModel.payDates.enumerated()), id: \.offset) { index, date in
                    DatePicker(
                        "Pay day \(index + 1)",
                        selection: Binding(get: { date }, set: { viewModel.setPayDate(at: index, to: $0) }),
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("incomeAnchorDatePicker_\(index)")

                    if viewModel.payDateCount > 1, let splitText = viewModel.splitAmountText(at: index) {
                        Text(splitText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("incomeSplitAmount_\(index)")
                    }
                }

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
            Text("Used to define this budget's periods and to track when this income actually arrives. Paid more than once per period? Add a pay day for each — the amount above splits evenly across them. Leave off for irregular income.")
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
    ) {}
}

#Preview("Edit") {
    let source = Wellspent_V1_IncomeSource.with {
        $0.id = 1
        $0.name = "Paycheck"
        $0.incomeType = .salary
        $0.defaultAmount = .with { $0.units = 2500; $0.currency = "USD" }
        $0.recurring = true
        $0.paymentFrequency = .monthly
    }
    let job = IncomeJobGrouping.Job(
        key: .init(name: source.name, budgetPersonID: source.budgetPersonID, incomeType: source.incomeType, paymentFrequency: source.paymentFrequency),
        rows: [.init(source: source, schedule: BudgetRESTMapping.IncomeSchedule(anchorDate: nil, earlyArrivalToleranceDays: 0))]
    )
    AddEditIncomeView(
        mode: .edit(job),
        budgetProfileID: "preview-budget",
        countryCode: "US",
        currencyCode: "USD",
        people: [.with { $0.id = 1; $0.userName = "Jane" }],
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) {}
}
