import SwiftUI
import WellSpentAPI

struct TransactionsListView: View {
    /// Local to this file, not a `Shared/` enum like `BudgetSection` — this
    /// is UI-local tab state, not a reusable domain concept.
    enum TransactionKind: Hashable {
        case variable
        case fixed
    }

    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String
    /// See `ExpensePlanView.selectedKind` — owned by `BudgetDetailView` so it
    /// can decide which toolbar button to show at the one nav-bar level
    /// that's actually rendered.
    @Binding var selectedKind: TransactionKind
    @Binding var isAddTransactionPresented: Bool
    @Binding var isAddFixedExpensePresented: Bool
    /// See `ExpensePlanView.isActive`.
    let isActive: Bool
    /// Owned by `BudgetDetailView` (see `TransactionReviewListView`'s doc
    /// comment) — read here (and passed into `FixedExpensesListView`) to
    /// filter confirmed-review matches out of the Variable list and show a
    /// pending-match hint, mirroring web's `TransactionsPanel.tsx`.
    var reviewViewModel: TransactionReviewViewModel? = nil
    let canEdit: Bool
    /// True when viewing an archived (past) period — see
    /// docs/features/budget-list-view-rework.md. Editing a Variable row's
    /// category stays reachable via `canEdit` alone (see
    /// `AddEditTransactionViewModel`'s `isLocked`); `canMutate` additionally
    /// requires the period not be archived, gating delete/exclude
    /// specifically (flag-for-review is left ungated by this, matching the
    /// backend, which doesn't restrict it).
    var isArchivedPeriod: Bool = false
    let searchQuery: String
    let filter: TransactionFilterOption

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @State private var viewModel: TransactionsViewModel?
    @State private var editingTransaction: Wellspent_V1_Transaction?
    @State private var markReviewTarget: Wellspent_V1_Transaction?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $selectedKind) {
                Text("Variable").tag(TransactionKind.variable)
                Text("Fixed").tag(TransactionKind.fixed)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .accessibilityIdentifier("transactionKindPicker")

            switch selectedKind {
            case .variable:
                Group {
                    if let viewModel {
                        content(viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                }
            case .fixed:
                FixedExpensesListView(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    authenticatedClient: authenticatedClient,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    isAddSheetPresented: $isAddFixedExpensePresented,
                    isActive: isActive && selectedKind == .fixed,
                    reviewViewModel: reviewViewModel,
                    canEdit: canEdit,
                    isArchivedPeriod: isArchivedPeriod,
                    searchQuery: searchQuery,
                    filter: filter
                )
            }
        }
        .navigationTitle("Transactions")
        .task {
            if viewModel == nil {
                viewModel = TransactionsViewModel(
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
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: TransactionsViewModel) -> some View {
        let reviews = reviewViewModel?.reviews ?? []
        let confirmedFiltered = viewModel.visibleTransactions(reviews: reviews)
        let visibleTransactions = TransactionFiltering.apply(
            confirmedFiltered,
            filter: filter,
            searchQuery: searchQuery,
            incomeCategoryID: viewModel.categories.first { $0.isSystem && $0.name == "Income" }?.id,
            overBudgetTransactionIDs: filter == .exceededOnly ? viewModel.overBudgetTransactionIDs : [],
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName
        )
        let dayGroups = TransactionDayGrouping.group(visibleTransactions)

        List {
            Section {
                LabeledContent("Total", value: viewModel.totalText)
                    .accessibilityIdentifier("transactionsTotal")
            }

            if viewModel.transactions.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if visibleTransactions.isEmpty {
                Text("No transactions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.transactions, id: \.id) { transaction in
                            transactionRow(transaction, viewModel: viewModel, reviews: reviews)
                                .swipeActions(edge: .trailing) {
                                    if canMutate && !transaction.isPlaidImported {
                                        Button("Delete", role: .destructive) {
                                            Task { await viewModel.delete(id: transaction.id) }
                                        }
                                    }
                                }
                        }
                    } header: {
                        Text(TransactionDayGrouping.headerText(for: group.id, localeIdentifier: localeIdentifier))
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.plain)
        .sheet(isPresented: $isAddTransactionPresented) {
            AddEditTransactionView(
                mode: .add,
                budgetPeriodID: budgetPeriodID,
                currencyCode: currencyCode,
                categories: viewModel.categories,
                paymentMethods: viewModel.paymentMethods,
                authenticatedClient: authenticatedClient
            ) { transaction in
                viewModel.addTransaction(transaction)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTransaction != nil },
            set: { if !$0 { editingTransaction = nil } }
        )) {
            if let editingTransaction {
                AddEditTransactionView(
                    mode: .edit(editingTransaction),
                    budgetPeriodID: budgetPeriodID,
                    currencyCode: currencyCode,
                    categories: viewModel.categories,
                    paymentMethods: viewModel.paymentMethods,
                    isArchivedPeriod: isArchivedPeriod,
                    authenticatedClient: authenticatedClient
                ) { updated in
                    viewModel.replaceTransaction(updated)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { markReviewTarget != nil },
            set: { if !$0 { markReviewTarget = nil } }
        )) {
            if let markReviewTarget {
                MarkForReviewSheet(
                    transaction: markReviewTarget,
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    authenticatedClient: authenticatedClient
                ) {
                    Task { await reviewViewModel?.load() }
                }
            }
        }
    }

    private func transactionRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel, reviews: [Wellspent_V1_TransactionReview]) -> some View {
        let isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
        let pendingMatchName = viewModel.pendingMatchName(for: transaction, reviews: reviews)

        let nameContent = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(transaction.name)
                    .foregroundStyle(.primary)
                if let pendingMatchName {
                    Text("(linked to \(pendingMatchName))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                if let categoryName = viewModel.categoryName(for: transaction.categoryID) {
                    ColorDotView(hex: viewModel.categoryColor(for: transaction.categoryID), diameter: 8)
                    Text(categoryName)
                }
                if let methodName = viewModel.paymentMethodName(for: transaction.paymentMethodID) {
                    Text("·")
                    ColorDotView(hex: viewModel.paymentMethodColor(for: transaction.paymentMethodID), diameter: 8)
                    Text(methodName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        return HStack {
            Group {
                if canEdit {
                    Button {
                        editingTransaction = transaction
                    } label: {
                        nameContent
                    }
                    .buttonStyle(.plain)
                } else {
                    nameContent
                }
            }
            .accessibilityIdentifier("transactionRow_\(transaction.name)")

            Spacer()

            Text(TransactionAmountFormatting.displayText(
                units: transaction.amount.units,
                nanos: transaction.amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
            .foregroundStyle(isReceived ? .green : .red)

            if canEdit {
                Button {
                    markReviewTarget = transaction
                } label: {
                    Image(systemName: "flag")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("flagForReview_\(transaction.name)")
            }

            if canMutate {
                Button {
                    Task { await viewModel.toggleExcluded(transaction) }
                } label: {
                    Image(systemName: transaction.isExcluded ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("excludeTransaction_\(transaction.name)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        TransactionsListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            selectedKind: .constant(.variable),
            isAddTransactionPresented: .constant(false),
            isAddFixedExpensePresented: .constant(false),
            isActive: true,
            canEdit: true,
            searchQuery: "",
            filter: .none
        )
    }
}
