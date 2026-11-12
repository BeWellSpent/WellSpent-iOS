import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Step 2 of `BudgetSetupFlow`. Hosts `AddEditIncomeViewModel` in `.add`
/// mode as-is (same view model the standalone Income panel uses) — each
/// successful add is followed by constructing a fresh instance so the form
/// resets, mirroring web's "add multiple, one RPC per Add tap" behavior.
/// `incomeType`/`paymentFrequency` are left at their `.add`-mode defaults
/// (SALARY / MONTHLY) rather than exposing pickers — matches web's
/// onboarding simplification; the full panel still exposes both post-setup.
struct IncomeSetupStepView: View {
    let budgetProfileID: String
    let countryCode: String
    let currencyCode: String
    let people: [Wellspent_V1_BudgetPerson]
    let restClient: WellSpentREST.Client
    let onContinue: () -> Void

    @State private var viewModel: AddEditIncomeViewModel
    @State private var addedSourceNames: [String] = []

    init(
        budgetProfileID: String,
        countryCode: String,
        currencyCode: String,
        people: [Wellspent_V1_BudgetPerson],
        restClient: WellSpentREST.Client,
        onContinue: @escaping () -> Void
    ) {
        self.budgetProfileID = budgetProfileID
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.people = people
        self.restClient = restClient
        self.onContinue = onContinue
        _viewModel = State(initialValue: AddEditIncomeViewModel(
            mode: .add,
            budgetProfileID: budgetProfileID,
            countryCode: countryCode,
            currencyCode: currencyCode,
            restClient: restClient
        ))
    }

    var body: some View {
        SetupStepScaffold(step: .income) {
            if !addedSourceNames.isEmpty {
                HomeSectionHeader(title: Text("Added so far"))
                SetupAddedList(items: addedSourceNames) { name in
                    SetupRowText(title: name, detail: "")
                }
            }

            HomeSectionHeader(title: Text("Add income"))
            addForm

            if let errorMessage = viewModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
        } action: {
            Button("Continue") { onContinue() }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("setupSkipButton")
        }
    }

    private var addForm: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    LabeledFieldBox(label: Text("Name")) {
                        TextField("e.g. Salary", text: $viewModel.name)
                            .accessibilityIdentifier("setupIncomeNameField")
                    }
                    .layoutPriority(1)
                    LabeledFieldBox(label: Text("Amount")) {
                        AmountTextField(text: $viewModel.amountText)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("setupIncomeAmountField")
                    }
                }

                if !people.isEmpty {
                    ColorDotPickerField(
                        title: "Who earns it",
                        selection: $viewModel.personID,
                        options: people.map { ColorDotOption(id: $0.id, name: $0.userName, hex: $0.color) },
                        noneOption: (id: Int64(0), label: "Unattributed"),
                        accessibilityIdentifier: "setupIncomePersonPicker"
                    )
                }

                Toggle("Recurring", isOn: $viewModel.recurring)
                    .tint(.green)

                if viewModel.showBeforeTaxToggle {
                    Toggle(isOn: $viewModel.beforeTax) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Before tax")
                            Text("We set aside an estimated tax reserve")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                }

                SetupAddButton(title: Text("Add income"), isWorking: viewModel.isSubmitting) {
                    Task {
                        let name = viewModel.name
                        if await viewModel.submit() {
                            addedSourceNames.append(name)
                            viewModel = AddEditIncomeViewModel(
                                mode: .add,
                                budgetProfileID: budgetProfileID,
                                countryCode: countryCode,
                                currencyCode: currencyCode,
                                restClient: restClient
                            )
                        }
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("setupAddIncomeButton")
            }
        }
    }
}

#Preview {
    NavigationStack {
        IncomeSetupStepView(
            budgetProfileID: "preview-budget",
            countryCode: "US",
            currencyCode: "USD",
            people: [.with { $0.id = 1; $0.userName = "Jane" }],
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        ) {}
    }
}
