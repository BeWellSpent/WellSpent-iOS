import SwiftUI
import WellSpentAPI
import WellSpentREST

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
    let restClient: WellSpentREST.Client
    let onFinish: () -> Void

    @State private var viewModel: AddSavingsSourceViewModel
    @State private var addedSources: [Wellspent_V1_SavingsSource] = []

    init(
        budgetProfileID: String,
        currencyCode: String,
        paymentMethods: [Wellspent_V1_PaymentMethod],
        restClient: WellSpentREST.Client,
        onFinish: @escaping () -> Void
    ) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.paymentMethods = paymentMethods
        self.restClient = restClient
        self.onFinish = onFinish
        _viewModel = State(initialValue: AddSavingsSourceViewModel(
            budgetProfileID: budgetProfileID,
            currencyCode: currencyCode,
            // No period to anchor to yet — a brand-new budget's first period
            // starts today, which is what the view model falls back to.
            periodStartDate: nil,
            restClient: restClient
        ))
    }

    var body: some View {
        SetupStepScaffold(step: .savings) {
            if !addedSources.isEmpty {
                HomeSectionHeader(title: Text("Added so far"))
                SetupAddedList(items: addedSources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                            .frame(width: 28, height: 28)
                            .background(Color.green.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)
                        SetupRowText(title: source.name, detail: "")
                    }
                }
            }

            HomeSectionHeader(title: Text("Add savings"))
            // Without a payment method there is nothing to save from; saying so beats a dead Add button.
            if paymentMethods.isEmpty {
                HomeCard {
                    Text("Add a payment method first — savings come out of one.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("setupSavingsNeedsPaymentMethod")
                }
            } else {
                addForm
            }

            if let errorMessage = viewModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
        } action: {
            Button("Finish setup") { onFinish() }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("setupSkipButton")
        }
    }

    private var addForm: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                // Even split, as on Register: a priority on Name squeezed Amount to nothing.
                HStack(alignment: .top, spacing: 10) {
                    LabeledFieldBox(label: Text("Name")) {
                        TextField("e.g. Holiday", text: $viewModel.name)
                            .accessibilityIdentifier("setupSavingsNameField")
                    }
                    LabeledFieldBox(label: Text("Amount")) {
                        AmountTextField(text: $viewModel.amountText)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("setupSavingsAmountField")
                    }
                }

                ColorDotPickerField(
                    title: "Comes out of",
                    selection: $viewModel.paymentMethodID,
                    options: paymentMethods.map {
                        ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                    },
                    noneOption: (id: "", label: "None"),
                    accessibilityIdentifier: "setupSavingsPaymentMethodPicker"
                )

                SavingsPaymentDaysGrid(selectedDays: $viewModel.paymentDays, daysInMonth: viewModel.daysInMonth)

                SetupAddButton(title: Text("Add savings"), isWorking: viewModel.isSubmitting) {
                    Task {
                        if let source = await viewModel.submit() {
                            addedSources.append(source)
                            viewModel = AddSavingsSourceViewModel(
                                budgetProfileID: budgetProfileID,
                                currencyCode: currencyCode,
                                periodStartDate: nil,
                                restClient: restClient
                            )
                        }
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("setupAddSavingsButton")
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
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        ) {}
    }
}
