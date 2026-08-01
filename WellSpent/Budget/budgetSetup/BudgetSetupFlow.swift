import SwiftUI
import WellSpentAPI

/// The 4-step budget setup wizard (Create -> People -> Income -> Payment
/// Methods), replacing the old single-form "New Budget" sheet. Mirrors
/// web's `BudgetSetupFlow.tsx`: one dialog whose content swaps per step
/// (not pushed navigation), a "Finish Later" exit once past step 0, and
/// each step's own Skip/Continue controls live in that step's content, not
/// the toolbar. See `CLAUDE.md` for the deliberate divergences from web
/// (cycle picker kept, immediate per-add People RPCs instead of
/// batch-on-continue, `onCreated` fires right after step 0 instead of only
/// at the very end).
struct BudgetSetupFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BudgetSetupViewModel
    @State private var createViewModel: CreateBudgetViewModel
    private let authenticatedClient: ProtocolClient
    private let currencyCode: String
    private let localeIdentifier: String
    private let onCreated: (Wellspent_V1_BudgetProfile) -> Void

    init(
        authenticatedClient: ProtocolClient,
        currencyCode: String,
        localeIdentifier: String,
        onCreated: @escaping (Wellspent_V1_BudgetProfile) -> Void
    ) {
        _viewModel = State(initialValue: BudgetSetupViewModel(authenticatedClient: authenticatedClient))
        _createViewModel = State(initialValue: CreateBudgetViewModel(authenticatedClient: authenticatedClient))
        self.authenticatedClient = authenticatedClient
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .create:
                    createStep
                case .people:
                    PeopleSetupStepView(viewModel: viewModel)
                case .income:
                    IncomeSetupStepView(
                        budgetProfileID: viewModel.profile?.id ?? "",
                        countryCode: viewModel.profile?.countryCode ?? "",
                        currencyCode: currencyCode,
                        people: viewModel.people,
                        authenticatedClient: authenticatedClient,
                        onContinue: { viewModel.advance() }
                    )
                case .paymentMethods:
                    PaymentMethodsSetupStepView(
                        people: viewModel.people,
                        authenticatedClient: authenticatedClient,
                        onFinish: { dismiss() }
                    )
                }
            }
            .navigationTitle("Step \(viewModel.step.rawValue + 1) of \(BudgetSetupViewModel.Step.allCases.count) — \(viewModel.step.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.step == .create {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                if let profile = await createViewModel.submit() {
                                    onCreated(profile)
                                    await viewModel.budgetCreated(profile)
                                }
                            }
                        } label: {
                            if createViewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Create")
                            }
                        }
                        .disabled(!createViewModel.canSubmit)
                        .accessibilityIdentifier("createBudgetButton")
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Finish Later") { dismiss() }
                            .accessibilityIdentifier("finishSetupLaterButton")
                    }
                }
            }
        }
    }

    private var createStep: some View {
        Form {
            Section {
                TextField("Budget name", text: $createViewModel.name)
                    .accessibilityIdentifier("budgetNameField")

                Picker("Cycle", selection: $createViewModel.cycle) {
                    ForEach(BudgetCycleLabel.selectable, id: \.self) { cycle in
                        Text(BudgetCycleLabel.text(for: cycle)).tag(cycle)
                    }
                }
                .accessibilityIdentifier("budgetCyclePicker")
            }

            if let errorMessage = createViewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("createBudgetErrorMessage")
                }
            }
        }
    }
}

#Preview {
    BudgetSetupFlow(
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        currencyCode: "USD",
        localeIdentifier: "en"
    ) { _ in }
}
