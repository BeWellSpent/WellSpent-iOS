import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Reachable from `EditFixedExpenseView` for any fixed expense with a
/// payment plan set. Hands the updated transaction + fixed expense back so
/// the caller can refresh without a full reload.
struct PayFixedExpenseInFullView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: PayFixedExpenseInFullViewModel
    private let onDone: (Wellspent_V1_Transaction, Wellspent_V1_FixedExpense) -> Void

    init(
        budgetProfileID: String,
        fixedExpenseID: String,
        currencyCode: String,
        remainingBalance: Wellspent_V1_Money,
        restClient: WellSpentREST.Client,
        onDone: @escaping (Wellspent_V1_Transaction, Wellspent_V1_FixedExpense) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: PayFixedExpenseInFullViewModel(
            budgetProfileID: budgetProfileID,
            fixedExpenseID: fixedExpenseID,
            currencyCode: currencyCode,
            remainingBalance: remainingBalance,
            restClient: restClient
        ))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountTextField(text: $viewModel.amountText)
                        .accessibilityIdentifier("payInFullAmountField")

                    DatePicker("Paid date", selection: $viewModel.paidDate, displayedComponents: .date)
                        .accessibilityIdentifier("payInFullDatePicker")
                } footer: {
                    Text("Settles the plan's remaining balance in one payment. Its end date doesn't change.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("payInFullErrorMessage")
                    }
                }
            }
            .sheetChrome(Text("Pay in Full")) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let result = await viewModel.submit() {
                                onDone(result.transaction, result.fixedExpense)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Confirm")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("confirmPayInFullButton")
                }
            }
        }
    }
}

#Preview {
    PayFixedExpenseInFullView(
        budgetProfileID: "preview-budget",
        fixedExpenseID: "fe-1",
        currencyCode: "USD",
        remainingBalance: .with { $0.units = 450; $0.currency = "USD" },
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _, _ in }
}
