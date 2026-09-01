import SwiftUI
import WellSpentAPI

/// The wizard's final step: recurring savings.
///
/// Comes after Payment methods, not at the end for its own sake — a savings
/// source spends from a payment method, so there is nothing to pick from until
/// that step has run. Reuses `AddSavingsSourceViewModel` unchanged, with a
/// fresh instance after each add so the form resets, the same pattern
/// `PaymentMethodsSetupStepView` established.
struct SavingsSetupStepView: View {
    let budgetProfileID: String
    let currencyCode: String
    let paymentMethods: [Wellspent_V1_PaymentMethod]
    let authenticatedClient: ProtocolClient
    let onFinish: () -> Void

    @State private var viewModel: AddSavingsSourceViewModel
    @State private var addedSources: [Wellspent_V1_SavingsSource] = []

    init(
        budgetProfileID: String,
        currencyCode: String,
        paymentMethods: [Wellspent_V1_PaymentMethod],
        authenticatedClient: ProtocolClient,
        onFinish: @escaping () -> Void
    ) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.paymentMethods = paymentMethods
        self.authenticatedClient = authenticatedClient
        self.onFinish = onFinish
        _viewModel = State(initialValue: AddSavingsSourceViewModel(
            budgetProfileID: budgetProfileID,
            currencyCode: currencyCode,
            // No period to anchor to yet — a brand-new budget's first period
            // starts today, which is what the view model falls back to.
            periodStartDate: nil,
            authenticatedClient: authenticatedClient
        ))
    }

    var body: some View {
        Form {
            Section {
                Text("Set money aside each period — an emergency fund, a holiday, anything you want kept apart from spending.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !addedSources.isEmpty {
                Section("Added so far") {
                    ForEach(addedSources, id: \.id) { source in
                        Text(source.name)
                    }
                }
            }

            // Without a payment method there is nothing to spend from, so the
            // form would refuse to submit no matter what was typed into it.
            // Saying so beats a permanently disabled Add button.
            if paymentMethods.isEmpty {
                Section {
                    Text("Add a payment method first — savings come out of one.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("setupSavingsNeedsPaymentMethod")
                }
            } else {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .accessibilityIdentifier("setupSavingsNameField")

                    AmountTextField(text: $viewModel.amountText)
                        .accessibilityIdentifier("setupSavingsAmountField")

                    ColorDotPickerField(
                        title: "Payment Method",
                        selection: $viewModel.paymentMethodID,
                        options: paymentMethods.map {
                            ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                        },
                        noneOption: (id: "", label: "None"),
                        accessibilityIdentifier: "setupSavingsPaymentMethodPicker"
                    )
                }

                Section {
                    SavingsPaymentDaysGrid(selectedDays: $viewModel.paymentDays, daysInMonth: viewModel.daysInMonth)
                }

                Section {
                    Button {
                        Task {
                            if let source = await viewModel.submit() {
                                addedSources.append(source)
                                viewModel = AddSavingsSourceViewModel(
                                    budgetProfileID: budgetProfileID,
                                    currencyCode: currencyCode,
                                    periodStartDate: nil,
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
                    .accessibilityIdentifier("setupAddSavingsButton")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button("Finish") { onFinish() }
                    .accessibilityIdentifier("setupSkipButton")
            }
        }
    }
}

#Preview {
    NavigationStack {
        SavingsSetupStepView(
            budgetProfileID: "preview",
            currencyCode: "USD",
            paymentMethods: [.with { $0.id = "pm"; $0.name = "Checking" }],
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        ) {}
    }
}
