import SwiftUI
import WellSpentAPI
import WellSpentREST

struct AddEditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: AddEditTransactionViewModel
    private let categories: [Wellspent_V1_Category]
    private let paymentMethods: [Wellspent_V1_PaymentMethod]
    private let onDone: (Wellspent_V1_Transaction) -> Void

    init(
        mode: AddEditTransactionViewModel.Mode,
        budgetPeriodID: String,
        currencyCode: String,
        categories: [Wellspent_V1_Category],
        paymentMethods: [Wellspent_V1_PaymentMethod],
        isArchivedPeriod: Bool = false,
        forceLocked: Bool = false,
        defaultCategoryID: Int32 = 0,
        defaultFlow: TransactionFlowKind = .spend,
        restClient: WellSpentREST.Client,
        onDone: @escaping (Wellspent_V1_Transaction) -> Void
    ) {
        _viewModel = Bindable(wrappedValue: AddEditTransactionViewModel(
            mode: mode,
            budgetPeriodID: budgetPeriodID,
            currencyCode: currencyCode,
            isArchivedPeriod: isArchivedPeriod,
            forceLocked: forceLocked,
            defaultCategoryID: defaultCategoryID,
            defaultFlow: defaultFlow,
            restClient: restClient
        ))
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.onDone = onDone
    }

    private var isEditing: Bool {
        if case .edit = viewModel.mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                flowSection
                detailsSection
                errorSection
            }
            .sheetChrome(isEditing ? Text("Edit Transaction") : Text("Add Transaction")) { dismiss() }
            .toolbar {
                // A full-width in-body button (as the mockup shows) would be a
                // one-off departure from every other Add/Edit sheet in this
                // app, all of which save via this same .confirmationAction
                // toolbar button — the established convention `SheetChrome`
                // itself was built around. Kept for consistency, not inertia.
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let transaction = await viewModel.submit() {
                                onDone(transaction)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            (isEditing ? Text("Save") : Text("Add"))
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("saveTransactionButton")
                }
            }
        }
    }

    /// Direction + amount read as their own zone, matching the mockup: a
    /// money-direction control immediately above the hero amount, both
    /// visually distinct from the attribute list below.
    @ViewBuilder
    private var amountSection: some View {
        Section {
            if viewModel.isLocked {
                Text("Only the category and what it was can be changed for this transaction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transactionLockedNotice")
            }

            Picker("Direction", selection: $viewModel.isReceived) {
                Text("Money Out").tag(false)
                Text("Money In").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isLocked)
            .accessibilityIdentifier("transactionFlowPicker")

            AmountHeroField(
                text: $viewModel.amountText,
                autoFocus: !isEditing,
                disabled: viewModel.isLocked,
                accessibilityIdentifier: "transactionAmountField"
            )
        }
    }

    /// "What was it?": the flow chips for the chosen direction and what that choice means.
    /// A card payment (added from the Payments tab) shows only its explanation.
    @ViewBuilder
    private var flowSection: some View {
        Section {
            if viewModel.flow != .payment {
                HStack(spacing: 8) {
                    ForEach(TransactionFlowKind.choices(moneyIn: viewModel.isReceived), id: \.self) { kind in
                        let selected = viewModel.flow == kind
                        Button {
                            viewModel.flow = kind
                        } label: {
                            Text(kind.label)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? Color.accentColor : .primary)
                                .background(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("transactionFlow_\(kind.rawValue)")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Text(viewModel.flow.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transactionFlowHint")
        } header: {
            Text("What was it?")
        }
    }

    /// One merged section — name, category, payment method, date, recurring —
    /// reading as a single cohesive list instead of the two separately-gapped
    /// `Form` sections this used to be, closer to the mockup's one continuous
    /// card of rows.
    @ViewBuilder
    private var detailsSection: some View {
        Section {
            TextField("Name", text: $viewModel.name)
                .disabled(viewModel.isLocked)
                .accessibilityIdentifier("transactionNameField")

            ColorDotPickerField(
                title: "Category",
                selection: $viewModel.categoryID,
                options: categories.map { ColorDotOption(id: $0.id, name: $0.name, hex: $0.color) },
                noneOption: (id: Int32(0), label: "None"),
                accessibilityIdentifier: "transactionCategoryPicker"
            )

            ColorDotPickerField(
                title: "Payment Method",
                selection: $viewModel.paymentMethodID,
                options: paymentMethods.map {
                    ColorDotOption(id: $0.id, name: $0.alias.isEmpty ? $0.name : $0.alias, hex: $0.color)
                },
                noneOption: (id: "", label: "None"),
                accessibilityIdentifier: "transactionPaymentMethodPicker"
            )
            .disabled(viewModel.isLocked)

            DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                .disabled(viewModel.isLocked)
                .accessibilityIdentifier("transactionDatePicker")

            Toggle("Recurring", isOn: $viewModel.recurring)
                .disabled(viewModel.isLocked)
                .accessibilityIdentifier("transactionRecurringToggle")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("transactionErrorMessage")
            }
        }
    }
}

private let previewCategories: [Wellspent_V1_Category] = [
    .with { $0.id = 1; $0.name = "Groceries" },
    .with { $0.id = 2; $0.name = "Dining" },
]
private let previewPaymentMethods: [Wellspent_V1_PaymentMethod] = [
    .with { $0.id = "pm-1"; $0.name = "Chase Visa" },
]

#Preview("Add") {
    AddEditTransactionView(
        mode: .add,
        budgetPeriodID: "preview-period",
        currencyCode: "USD",
        categories: previewCategories,
        paymentMethods: previewPaymentMethods,
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}

#Preview("Edit — Received") {
    AddEditTransactionView(
        mode: .edit(.with {
            $0.id = "tx-1"
            $0.name = "Refund"
            $0.amount = .with { $0.units = -20; $0.currency = "USD" }
            $0.categoryID = 1
            $0.paymentMethodID = "pm-1"
        }),
        budgetPeriodID: "preview-period",
        currencyCode: "USD",
        categories: previewCategories,
        paymentMethods: previewPaymentMethods,
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
    ) { _ in }
}
