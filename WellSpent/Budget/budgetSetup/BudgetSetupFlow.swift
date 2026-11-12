import SwiftUI
import WellSpentAPI
import WellSpentREST

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
    private let restClient: WellSpentREST.Client
    private let currencyCode: String
    private let localeIdentifier: String
    private let onCreated: (Wellspent_V1_BudgetProfile) -> Void
    private let onCancelled: () -> Void
    @State private var isConfirmingCancel = false

    init(
        restClient: WellSpentREST.Client,
        currencyCode: String,
        localeIdentifier: String,
        onCancelled: @escaping () -> Void = {},
        onCreated: @escaping (Wellspent_V1_BudgetProfile) -> Void
    ) {
        _viewModel = State(initialValue: BudgetSetupViewModel(restClient: restClient))
        _createViewModel = State(initialValue: CreateBudgetViewModel(restClient: restClient))
        self.restClient = restClient
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
                        restClient: restClient,
                        onFinish: { viewModel.advance() }
                    )
                case .income:
                    IncomeSetupStepView(
                        budgetProfileID: viewModel.profile?.id ?? "",
                        countryCode: viewModel.profile?.countryCode ?? "",
                        currencyCode: currencyCode,
                        people: viewModel.people,
                        restClient: restClient,
                        onContinue: { viewModel.advance() }
                    )
                case .savings:
                    SavingsSetupStepView(
                        budgetProfileID: viewModel.profile?.id ?? "",
                        currencyCode: currencyCode,
                        paymentMethods: viewModel.paymentMethods,
                        restClient: restClient,
                        onFinish: { dismiss() }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.step == .create {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton { dismiss() }
                    }
                } else {
                    // Asks before deleting anything, so the usual ✕ can't lose a budget by muscle memory.
                    ToolbarItem(placement: .cancellationAction) {
                        Button { isConfirmingCancel = true } label: {
                            Label("Cancel Setup", systemImage: "xmark")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("cancelSetupButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish Later") { dismiss() }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("finishSetupLaterButton")
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
        SetupStepScaffold(step: .create) {
            HomeCard {
                LabeledFieldBox(label: Text("Budget name")) {
                    TextField("Budget name", text: $createViewModel.name)
                        .accessibilityIdentifier("budgetNameField")
                }
            }

            HomeSectionHeader(title: Text("How often do you budget?"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(BudgetCycleLabel.selectable, id: \.self) { cycle in
                    cycleCard(cycle)
                }
            }
            .accessibilityIdentifier("budgetCyclePicker")

            Text("Once you add income with pay dates, periods follow your paydays instead of the calendar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if let errorMessage = createViewModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
                    .accessibilityIdentifier("createBudgetErrorMessage")
            }
        } action: {
            Button {
                Task {
                    if let profile = await createViewModel.submit() {
                        onCreated(profile)
                        await viewModel.budgetCreated(profile)
                    }
                }
            } label: {
                if createViewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Create budget")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!createViewModel.canSubmit)
            .accessibilityIdentifier("createBudgetButton")
        }
    }

    private func cycleCard(_ cycle: Wellspent_V1_BudgetCycle) -> some View {
        let isSelected = createViewModel.cycle == cycle
        return Button {
            createViewModel.cycle = cycle
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(BudgetCycleLabel.text(for: cycle))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(BudgetCycleLabel.hint(for: cycle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    BudgetSetupFlow(
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
        currencyCode: "USD",
        localeIdentifier: "en"
    ) { _ in }
}
