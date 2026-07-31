import SwiftUI
import WellSpentAPI

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
        authenticatedClient: ProtocolClient,
        onDone: @escaping (Wellspent_V1_IncomeSource) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddEditIncomeViewModel(
            mode: mode,
            budgetProfileID: budgetProfileID,
            countryCode: countryCode,
            currencyCode: currencyCode,
            authenticatedClient: authenticatedClient
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
            .navigationTitle(isEditing ? "Edit Income" : "Add Income")
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
                            Text(isEditing ? "Save" : "Add")
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

            TextField("Amount", text: $viewModel.amountText)
                .keyboardType(.decimalPad)
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
    }

    @ViewBuilder
    private var attributionSection: some View {
        Section {
            Picker("Person", selection: $viewModel.personID) {
                Text("Unattributed").tag(Int64(0))
                ForEach(people, id: \.id) { person in
                    Text(person.userName).tag(person.id)
                }
            }
            .accessibilityIdentifier("incomePersonPicker")
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
