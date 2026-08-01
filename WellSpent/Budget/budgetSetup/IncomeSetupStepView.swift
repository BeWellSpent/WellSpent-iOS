import SwiftUI
import WellSpentAPI

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
    let authenticatedClient: ProtocolClient
    let onContinue: () -> Void

    @State private var viewModel: AddEditIncomeViewModel
    @State private var addedSources: [Wellspent_V1_IncomeSource] = []

    init(
        budgetProfileID: String,
        countryCode: String,
        currencyCode: String,
        people: [Wellspent_V1_BudgetPerson],
        authenticatedClient: ProtocolClient,
        onContinue: @escaping () -> Void
    ) {
        self.budgetProfileID = budgetProfileID
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.people = people
        self.authenticatedClient = authenticatedClient
        self.onContinue = onContinue
        _viewModel = State(initialValue: AddEditIncomeViewModel(
            mode: .add,
            budgetProfileID: budgetProfileID,
            countryCode: countryCode,
            currencyCode: currencyCode,
            authenticatedClient: authenticatedClient
        ))
    }

    var body: some View {
        Form {
            if !addedSources.isEmpty {
                Section("Added so far") {
                    ForEach(addedSources, id: \.id) { source in
                        Text(source.name)
                    }
                }
            }

            Section {
                TextField("Name", text: $viewModel.name)
                    .accessibilityIdentifier("setupIncomeNameField")

                AmountTextField(text: $viewModel.amountText)
                    .accessibilityIdentifier("setupIncomeAmountField")

                Toggle("Recurring", isOn: $viewModel.recurring)

                if viewModel.showBeforeTaxToggle {
                    Toggle("Before tax", isOn: $viewModel.beforeTax)
                }

                if !people.isEmpty {
                    Picker("Person", selection: $viewModel.personID) {
                        Text("Unattributed").tag(Int64(0))
                        ForEach(people, id: \.id) { person in
                            Text(person.userName).tag(person.id)
                        }
                    }
                }

                Button {
                    Task {
                        if let source = await viewModel.submit() {
                            addedSources.append(source)
                            viewModel = AddEditIncomeViewModel(
                                mode: .add,
                                budgetProfileID: budgetProfileID,
                                countryCode: countryCode,
                                currencyCode: currencyCode,
                                authenticatedClient: authenticatedClient
                            )
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
                .accessibilityIdentifier("setupAddIncomeButton")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button("Continue") { onContinue() }
                    .accessibilityIdentifier("setupSkipButton")
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
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        ) {}
    }
}
