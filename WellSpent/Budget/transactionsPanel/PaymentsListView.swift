import SwiftUI
import WellSpentAPI
import WellSpentREST
import os

/// Card-payment (system "Payment" category) rows — extracted out of
/// `TransactionsListView` (issue #76 carved them out of Variable; the
/// Overview/Plan nav rework, docs/features/overview-plan-navigation-rework.md,
/// then carved this whole tab out of `TransactionsListView` into its own
/// sibling sub-tab under the new Overview destination, alongside Transactions
/// and Review). Owns its own `TransactionsViewModel` instance — same
/// independent-per-leaf-view pattern `FixedExpensesListView` already uses
/// relative to the Variable tab, rather than sharing one instance across
/// sibling files.
struct PaymentsListView: View {
    private static let logger = AppLogger.logger("Payments")

    /// `Wellspent_V1_Transaction` isn't `Identifiable`, so `.sheet(item:)`
    /// needs a wrapper — mirrors `TransactionsListView.ActiveSheet`, just
    /// with the one case this tab needs.
    private enum ActiveSheet: Identifiable {
        case editTransaction(Wellspent_V1_Transaction)

        var id: String {
            switch self {
            case .editTransaction(let transaction): return "editTransaction-\(transaction.id)"
            }
        }
    }

    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client
    let currencyCode: String
    let localeIdentifier: String
    @Binding var isAddTransactionPresented: Bool
    /// See `ExpensePlanView.isActive`.
    let isActive: Bool
    /// Owned by `BudgetDetailView` — see `TransactionsListView.reviewViewModel`.
    var reviewViewModel: TransactionReviewViewModel? = nil
    let canEdit: Bool
    /// See `TransactionsListView.isArchivedPeriod`.
    var isArchivedPeriod: Bool = false
    let searchQuery: String

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @Environment(SessionStore.self) private var session
    @State private var viewModel: TransactionsViewModel?
    @State private var activeSheet: ActiveSheet?

    @State private var toastState = ToastState()
    /// Optimistically hidden while a swipe-delete's undo window is open — see
    /// `TransactionsListView.pendingDeleteIDs`.
    @State private var pendingDeleteIDs: Set<String> = []

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Payments")
        .task {
            if viewModel == nil {
                viewModel = TransactionsViewModel(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    currentUserID: session.userID,
                    restClient: authenticatedRESTClient
                )
            }
            await viewModel?.load()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                Task { await viewModel?.load() }
            }
        }
        // See `TransactionsListView`'s identical handler — a confirmed match
        // in Review mutates `reviewViewModel.reviews` in place, which this
        // view (mounted off-screen while another Overview sub-tab is active)
        // doesn't reliably redraw from on its own.
        .onChange(of: reviewViewModel?.reviews) { _, _ in
            Task { await viewModel?.load() }
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    /// Mirrors `TransactionsListView.content(viewModel:)`'s shape at this
    /// tab's level of behavior: search + day-grouping only, no flag-for-review,
    /// installment split, or create-fixed-from-transaction — those are
    /// Variable-spend-specific (issue #76).
    @ViewBuilder
    private func content(viewModel: TransactionsViewModel) -> some View {
        let reviews = reviewViewModel?.reviews ?? []
        let paymentCategoryID = viewModel.categories.first { $0.isSystem(.payment) }?.id ?? 0
        let visibleTransactions = TransactionFiltering.apply(
            viewModel.paymentTransactions(reviews: reviews),
            searchQuery: searchQuery,
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName
        )
        // Optimistically hidden during a swipe-delete's undo window.
        .filter { !pendingDeleteIDs.contains($0.id) }
        let dayGroups = TransactionDayGrouping.group(visibleTransactions)

        List {
            Section {
                summaryCard(viewModel: viewModel, reviews: reviews)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if viewModel.transactions.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if visibleTransactions.isEmpty {
                Text("No transactions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.transactions, id: \.id) { transaction in
                            row(transaction, viewModel: viewModel)
                                .swipeActions(edge: .leading) {
                                    if canEdit {
                                        Button {
                                            activeSheet = .editTransaction(transaction)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                        .accessibilityIdentifier("editTransaction_\(transaction.name)")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    if canMutate {
                                        Button {
                                            requestToggleExcluded(transaction, viewModel: viewModel)
                                        } label: {
                                            Label(transaction.isExcluded ? "Include" : "Exclude", systemImage: transaction.isExcluded ? "eye" : "eye.slash")
                                        }
                                        .tint(.gray)
                                        .accessibilityIdentifier("excludeTransaction_\(transaction.name)")
                                    }
                                    if canMutate && !transaction.isPlaidImported {
                                        Button(role: .destructive) {
                                            requestDelete(transaction, viewModel: viewModel)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .accessibilityIdentifier("deleteTransaction_\(transaction.name)")
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
        .toastOverlay(toastState)
        .sheet(isPresented: $isAddTransactionPresented) {
            AddEditTransactionView(
                mode: .add,
                budgetPeriodID: budgetPeriodID,
                currencyCode: currencyCode,
                categories: viewModel.categories,
                paymentMethods: viewModel.paymentMethods,
                defaultCategoryID: paymentCategoryID,
                restClient: authenticatedRESTClient
            ) { transaction in
                viewModel.addTransaction(transaction)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editTransaction(let transaction):
                AddEditTransactionView(
                    mode: .edit(transaction),
                    budgetPeriodID: budgetPeriodID,
                    currencyCode: currencyCode,
                    categories: viewModel.categories,
                    paymentMethods: viewModel.paymentMethods,
                    isArchivedPeriod: isArchivedPeriod,
                    restClient: authenticatedRESTClient
                ) { updated in
                    viewModel.replaceTransaction(updated)
                }
            }
        }
    }

    /// "Payments this period" card — reuses the already-computed client-side
    /// sum `paymentsTotalText`; no server analog exists for this tab (see
    /// that property's own doc comment), so there's no new arithmetic here.
    private func summaryCard(viewModel: TransactionsViewModel, reviews: [Wellspent_V1_TransactionReview]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Payments this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.paymentsTotalText(reviews: reviews))
                .font(.title2.bold())
                .accessibilityIdentifier("paymentsTotal")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityIdentifier("paymentsSummaryCard")
    }

    private func row(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        let isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)

        let nameContent = VStack(alignment: .leading, spacing: 2) {
            Text(transaction.name)
                .foregroundStyle(.primary)
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
            nameContent
                .accessibilityIdentifier("paymentRow_\(transaction.name)")

            Spacer()

            Text(TransactionAmountFormatting.displayText(
                units: transaction.amount.units,
                nanos: transaction.amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
            .foregroundStyle(isReceived ? .green : .red)
        }
    }

    /// Toast+Undo instead of `.confirmationDialog` for Delete (issue #92) —
    /// see `TransactionsListView.requestDelete`, mirrored here since this is
    /// now a separate view with its own `TransactionsViewModel` instance.
    private func requestDelete(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) {
        pendingDeleteIDs.insert(transaction.id)
        Self.logger.info("staged delete transactionID=\(transaction.id, privacy: .public)")
        let message = String(localized: "Transaction deleted", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        let id = transaction.id
        toastState.show(
            message,
            onUndo: { pendingDeleteIDs.remove(id) },
            onExpire: { Task { await viewModel.delete(id: id) } }
        )
    }

    /// Exclude/Include gets toast+Undo — see
    /// `TransactionsListView.requestToggleExcluded`'s identical doc comment
    /// for why the undo closure re-reads the row rather than reusing the
    /// stale snapshot.
    private func requestToggleExcluded(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) {
        let id = transaction.id
        Task {
            await viewModel.toggleExcluded(transaction)
            guard let updated = viewModel.transactions.first(where: { $0.id == id }) else { return }
            Self.logger.info("toggled excluded transactionID=\(id, privacy: .public) isExcluded=\(updated.isExcluded, privacy: .public)")
            let message = updated.isExcluded
                ? String(localized: "Transaction excluded", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                : String(localized: "Transaction included", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
            toastState.show(message, onUndo: {
                Task {
                    if let current = viewModel.transactions.first(where: { $0.id == id }) {
                        await viewModel.toggleExcluded(current)
                    }
                }
            })
        }
    }
}

#Preview {
    NavigationStack {
        PaymentsListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            isAddTransactionPresented: .constant(false),
            isActive: true,
            canEdit: true,
            searchQuery: ""
        )
    }
}
