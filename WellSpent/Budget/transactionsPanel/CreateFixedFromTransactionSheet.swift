import SwiftUI
import WellSpentAPI

/// Turns a variable transaction into a recurring fixed expense; the backend
/// auto-confirms the match, so the transaction is excluded on success.
struct CreateFixedFromTransactionSheet: View {
    let transaction: Wellspent_V1_Transaction
    let budgetPeriodID: String
    let authenticatedClient: ProtocolClient
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateFixedFromTransactionViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .sheetChrome(Text("Create a fixed expense")) { dismiss() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel?.submit() == true {
                                onCreated()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!(viewModel?.canSubmit ?? false))
                    .accessibilityIdentifier("createFixedFromTransactionButton")
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = CreateFixedFromTransactionViewModel(
                    transaction: transaction,
                    budgetPeriodID: budgetPeriodID,
                    authenticatedClient: authenticatedClient
                )
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: CreateFixedFromTransactionViewModel) -> some View {
        Form {
            Section {
                TextField("Name", text: Binding(
                    get: { viewModel.name },
                    set: { viewModel.name = $0 }
                ))
                .accessibilityIdentifier("createFixedFromTransactionName")
            } footer: {
                Text("This transaction will be matched to the new fixed expense and marked paid.")
            }

            Section {
                DatePicker(
                    "First due date",
                    selection: Binding(
                        get: { viewModel.startDate },
                        set: { viewModel.setStartDate($0) }
                    ),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("createFixedFromTransactionStartDatePicker")

                Picker("Repeats", selection: Binding(get: { viewModel.frequencyUnit }, set: viewModel.setFrequencyUnit)) {
                    Text("Monthly").tag(Wellspent_V1_FrequencyUnit.month)
                    Text("Weekly").tag(Wellspent_V1_FrequencyUnit.week)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("createFixedFromTransactionFrequencyPicker")

                if viewModel.frequencyUnit == .week {
                    Stepper("Every \(viewModel.intervalWeeks) week(s)", value: Binding(get: { viewModel.intervalWeeks }, set: viewModel.setIntervalWeeks), in: 1...52)
                } else {
                    Stepper("Every \(viewModel.intervalMonths) month(s)", value: Binding(get: { viewModel.intervalMonths }, set: viewModel.setIntervalMonths), in: 1...24)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }
}

#Preview {
    CreateFixedFromTransactionSheet(
        transaction: .with {
            $0.id = "tx-1"
            $0.name = "Netflix"
            $0.amount = .with { $0.units = 15; $0.currency = "USD" }
            $0.transactionTypeID = 2
        },
        budgetPeriodID: "preview-period",
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        onCreated: {}
    )
}
