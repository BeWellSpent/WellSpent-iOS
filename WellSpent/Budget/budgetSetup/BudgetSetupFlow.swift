import SwiftUI
import WellSpentAPI

/// The budget setup wizard (Create -> People -> Payment Methods -> Income
/// -> Savings). Mirrors web's `BudgetSetupFlow.tsx`: one sheet whose content
/// swaps per step (not pushed navigation), a "Finish Later" exit once past
/// step 0, and each step's own Skip/Continue controls living in that step's
/// content rather than the toolbar. See `CLAUDE.md` for the deliberate
/// divergences from web (cycle picker kept, immediate per-add People RPCs
/// instead of batch-on-continue, `onCreated` fires right after step 0 instead
/// of only at the very end).
///
/// Cancelling is available at every step, and past step 0 it deletes the
/// budget rather than merely closing the sheet — the profile already exists by
/// then, so anything less would leave a half-built budget behind.
struct BudgetSetupFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BudgetSetupViewModel
    @State private var createViewModel: CreateBudgetViewModel
    private let authenticatedClient: ProtocolClient
    private let currencyCode: String
    private let localeIdentifier: String
    private let onCreated: (Wellspent_V1_BudgetProfile) -> Void
    private let onCancelled: () -> Void
    @State private var isConfirmingCancel = false

    init(
        authenticatedClient: ProtocolClient,
        currencyCode: String,
        localeIdentifier: String,
        onCancelled: @escaping () -> Void = {},
        onCreated: @escaping (Wellspent_V1_BudgetProfile) -> Void
    ) {
        _viewModel = State(initialValue: BudgetSetupViewModel(authenticatedClient: authenticatedClient))
        _createViewModel = State(initialValue: CreateBudgetViewModel(authenticatedClient: authenticatedClient))
        self.authenticatedClient = authenticatedClient
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.onCancelled = onCancelled
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
                case .paymentMethods:
                    PaymentMethodsSetupStepView(
                        people: viewModel.people,
                        authenticatedClient: authenticatedClient,
                        onFinish: { viewModel.advance() }
                    )
                case .income:
                    IncomeSetupStepView(
                        budgetProfileID: viewModel.profile?.id ?? "",
                        countryCode: viewModel.profile?.countryCode ?? "",
                        currencyCode: currencyCode,
                        people: viewModel.people,
                        authenticatedClient: authenticatedClient,
                        onContinue: { viewModel.advance() }
                    )
                case .savings:
                    SavingsSetupStepView(
                        budgetProfileID: viewModel.profile?.id ?? "",
                        currencyCode: currencyCode,
                        paymentMethods: viewModel.paymentMethods,
                        authenticatedClient: authenticatedClient,
                        onFinish: { dismiss() }
                    )
                }
            }
            .sheetChrome(Text("Step \(viewModel.step.rawValue + 1) of \(BudgetSetupViewModel.Step.allCases.count) — \(viewModel.step.title)"))
            .toolbar {
                if viewModel.step == .create {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton { dismiss() }
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
                    // Destructive, so it does not sit where "Cancel" normally
                    // does — someone reaching for the usual dismiss must not
                    // delete their budget by muscle memory.
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Cancel Setup", role: .destructive) { isConfirmingCancel = true }
                            .accessibilityIdentifier("cancelSetupButton")
                    }
                }
            }
            // Loaded on arrival rather than kept live: the previous step is
            // what creates them, so anything fetched earlier would be empty.
            .task(id: viewModel.step) {
                if viewModel.step == .savings {
                    await viewModel.loadPaymentMethods()
                }
            }
            .confirmationDialog(
                "Cancel setup?",
                isPresented: $isConfirmingCancel,
                titleVisibility: .visible
            ) {
                Button("Delete budget", role: .destructive) {
                    Task {
                        if await viewModel.cancel() {
                            onCancelled()
                            dismiss()
                        }
                    }
                }
                Button("Keep setting up", role: .cancel) {}
            } message: {
                Text("This deletes the budget and everything added to it — people, payment methods, income and savings. Any invitation already sent will stop working.")
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
