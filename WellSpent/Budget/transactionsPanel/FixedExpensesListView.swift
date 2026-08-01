import SwiftUI
import WellSpentAPI

struct FixedExpensesListView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String
    /// See `ExpensePlanView.isAddCategoryPresented` / `.isActive` — owned by
    /// `BudgetDetailView` and threaded through `TransactionsListView`.
    @Binding var isAddSheetPresented: Bool
    let isActive: Bool
    /// See `TransactionsListView.reviewViewModel` — used here to render each
    /// confirmed match as an expandable linked sub-row.
    var reviewViewModel: TransactionReviewViewModel? = nil
    let canEdit: Bool

    @State private var viewModel: FixedExpensesViewModel?
    @State private var editingTransaction: Wellspent_V1_Transaction?
    @State private var markingPaidTransaction: Wellspent_V1_Transaction?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel?.load()
        }
        .task {
            if viewModel == nil {
                viewModel = FixedExpensesViewModel(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                Task { await viewModel?.load() }
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: FixedExpensesViewModel) -> some View {
        List {
            Section {
                LabeledContent("Total", value: viewModel.totalText)
                    .accessibilityIdentifier("fixedExpensesTotal")
            }

            if viewModel.transactions.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if viewModel.transactions.isEmpty {
                Text("No fixed expenses yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.transactions, id: \.id) { transaction in
                    FixedExpenseRow(
                        transaction: transaction,
                        viewModel: viewModel,
                        linkedReviews: viewModel.linkedReviews(for: transaction, reviews: reviewViewModel?.reviews ?? []),
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier,
                        canEdit: canEdit,
                        onEdit: { editingTransaction = transaction },
                        onMarkPaid: { markingPaidTransaction = transaction }
                    )
                }
                .onDelete(perform: canEdit ? { offsets in
                    for index in offsets {
                        let transaction = viewModel.transactions[index]
                        Task { await viewModel.delete(transaction) }
                    }
                } : nil)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddFixedExpenseView(
                budgetProfileID: budgetProfileID,
                currencyCode: currencyCode,
                categories: viewModel.categories,
                paymentMethods: viewModel.paymentMethods,
                authenticatedClient: authenticatedClient
            ) { expense, transaction in
                viewModel.addFromCreate(expense: expense, transaction: transaction)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTransaction != nil },
            set: { if !$0 { editingTransaction = nil } }
        )) {
            if let editingTransaction, let template = viewModel.template(for: editingTransaction) {
                EditFixedExpenseView(
                    expense: template,
                    currencyCode: currencyCode,
                    categories: viewModel.categories,
                    paymentMethods: viewModel.paymentMethods,
                    authenticatedClient: authenticatedClient
                ) { _ in
                    Task { await viewModel.handleTemplateUpdated() }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { markingPaidTransaction != nil },
            set: { if !$0 { markingPaidTransaction = nil } }
        )) {
            if let markingPaidTransaction {
                MarkAsPaidView(transaction: markingPaidTransaction, currencyCode: currencyCode) { amount, date in
                    Task { await viewModel.markPaid(markingPaidTransaction, paidAmount: amount, paidAt: date) }
                }
            }
        }
    }
}

/// A Fixed transaction row that expands (only when it has confirmed review
/// matches) to reveal the linked Variable transaction(s) underneath —
/// mirrors web's `TxRow.tsx` expand/collapse behavior. Each linked review
/// carries its own denormalized `transactionName`/`transactionAmount`, so no
/// separate fetch of the (excluded) Variable transaction is needed.
private struct FixedExpenseRow: View {
    let transaction: Wellspent_V1_Transaction
    let viewModel: FixedExpensesViewModel
    let linkedReviews: [Wellspent_V1_TransactionReview]
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onEdit: () -> Void
    let onMarkPaid: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !linkedReviews.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("expandFixedExpense_\(transaction.name)")
                }

                Group {
                    if canEdit {
                        Button {
                            onEdit()
                        } label: {
                            fixedExpenseNameContent
                        }
                        .buttonStyle(.plain)
                    } else {
                        fixedExpenseNameContent
                    }
                }
                .accessibilityIdentifier("fixedExpenseRow_\(transaction.name)")

                Spacer()

                Text(MoneyFormatting.format(
                    units: transaction.amount.units,
                    nanos: transaction.amount.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))

                if canEdit {
                    Button {
                        if transaction.isPaid {
                            Task { await viewModel.unmark(transaction) }
                        } else {
                            onMarkPaid()
                        }
                    } label: {
                        Image(systemName: transaction.isPaid ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(transaction.isPaid ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(transaction.isPaid ? "unmarkPaid_\(transaction.name)" : "markPaid_\(transaction.name)")

                    Button {
                        Task { await viewModel.toggleExcluded(transaction) }
                    } label: {
                        Image(systemName: transaction.isExcluded ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("excludeFixedExpense_\(transaction.name)")
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(linkedReviews, id: \.id) { review in
                        HStack {
                            Text(review.transactionName)
                                .font(.caption)
                            Spacer()
                            Text(MoneyFormatting.format(
                                units: review.transactionAmount.units,
                                nanos: review.transactionAmount.nanos,
                                currencyCode: currencyCode,
                                localeIdentifier: localeIdentifier
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 6)
                .accessibilityIdentifier("linkedTransactions_\(transaction.name)")
            }
        }
    }

    private var fixedExpenseNameContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(transaction.name)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                if let categoryName = viewModel.categoryName(for: transaction.categoryID) {
                    Text(categoryName)
                }
                if let methodName = viewModel.paymentMethodName(for: transaction.paymentMethodID) {
                    Text("· \(methodName)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        FixedExpensesListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            isAddSheetPresented: .constant(false),
            isActive: true,
            canEdit: true
        )
    }
}
