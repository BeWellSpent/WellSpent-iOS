import SwiftUI
import WellSpentAPI

/// Converts a variable purchase into a card installment plan.
///
/// The sheet computes the split for display only; `CreateInstallmentPlan` does
/// the real arithmetic and returns the authoritative amounts.
struct InstallmentPlanSheet: View {
    let transaction: Wellspent_V1_Transaction
    let budgetPeriodID: String
    let currencyCode: String
    let localeIdentifier: String
    let authenticatedClient: ProtocolClient
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: InstallmentPlanViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Split into installments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create plan") {
                        Task {
                            if await viewModel?.submit() == true {
                                onCreated()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel?.isSubmitting ?? true)
                    .accessibilityIdentifier("createInstallmentPlanButton")
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = InstallmentPlanViewModel(
                    transaction: transaction,
                    budgetPeriodID: budgetPeriodID,
                    authenticatedClient: authenticatedClient
                )
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: InstallmentPlanViewModel) -> some View {
        @Bindable var viewModel = viewModel
        Form {
            Section {
                Stepper(
                    "Number of payments: \(viewModel.payments)",
                    value: Binding(
                        get: { viewModel.payments },
                        set: { viewModel.setPayments($0) }
                    ),
                    in: InstallmentPlan.minPayments...InstallmentPlan.maxPayments
                )
                .accessibilityIdentifier("installmentPaymentsStepper")

                DatePicker(
                    "First payment",
                    selection: Binding(
                        get: { viewModel.firstPayment },
                        set: { viewModel.setFirstPayment($0) }
                    ),
                    displayedComponents: .date
                )

                DatePicker(
                    "Last payment",
                    selection: Binding(
                        get: { viewModel.endDate },
                        set: { viewModel.setEndDate($0) }
                    ),
                    displayedComponents: .date
                )
            } footer: {
                Text("Defaults to next month — a card bills the statement after the one you bought in.")
            }

            Section {
                LabeledContent("Each payment", value: perPaymentText(viewModel))
                    .accessibilityIdentifier("installmentPerPayment")
            } footer: {
                Text("The original purchase stays visible but stops counting toward totals.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    private func perPaymentText(_ viewModel: InstallmentPlanViewModel) -> String {
        MoneyFormatting.format(
            units: viewModel.perPayment.units,
            nanos: viewModel.perPayment.nanos,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }
}

#Preview {
    InstallmentPlanSheet(
        transaction: .with {
            $0.id = "tx-1"
            $0.name = "Laptop"
            $0.amount = .with { $0.units = 1000; $0.currency = "USD" }
            $0.transactionTypeID = 2
        },
        budgetPeriodID: "preview-period",
        currencyCode: "USD",
        localeIdentifier: "en",
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        onCreated: {}
    )
}
