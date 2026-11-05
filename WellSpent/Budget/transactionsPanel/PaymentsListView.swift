import SwiftUI
import WellSpentAPI
import WellSpentREST
import os

/// Card-payment (system "Payment" category) rows — extracted out of
/// `TransactionsListView` (issue #76 carved them out of Variable; the
/// Overview/Plan nav rework, docs/features/overview-plan-navigation-rework.md,
/// then carved this whole tab out of `TransactionsListView` into its own
/// sibling sub-tab under the new Overview destination, alongside Transactions
/// and Review). Owns its own `TransactionsViewModel` instance, independent
/// of the merged Variable+Fixed `TransactionsListView`'s own instance,
/// rather than sharing one across sibling files.
struct PaymentsListView: View {
    private static let logger = AppLogger.logger("Payments")

    /// `Wellspent_V1_Transaction` isn't `Identifiable`, so `.sheet(item:)`
    /// needs a wrapper — mirrors `TransactionsListView.ActiveSheet`, just
    /// with the one case this tab needs.
    private enum ActiveSheet: Identifiable {
        case editTransaction(Wellspent_V1_Transaction)
        case moveToPeriod(Wellspent_V1_Transaction)

        var id: String {
            switch self {
            case .editTransaction(let transaction): return "editTransaction-\(transaction.id)"
            case .moveToPeriod(let transaction): return "moveToPeriod-\(transaction.id)"
            }
        }
    }

    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client
    let currencyCode: String
    let localeIdentifier: String
    /// See `TransactionsListView.periods`.
    var periods: [Wellspent_V1_BudgetPeriod] = []
    @Binding var isAddTransactionPresented: Bool
    /// See `ExpensePlanView.isActive`.
    let isActive: Bool
    /// Owned by `BudgetDetailView` — see `TransactionsListView.reviewViewModel`.
    var reviewViewModel: TransactionReviewViewModel? = nil
    let canEdit: Bool
    /// See `TransactionsListView.isArchivedPeriod`.
    var isArchivedPeriod: Bool = false
    let searchQuery: String
    /// See `TransactionsViewModel.onDataChanged`.
    var onDataChanged: () -> Void = {}

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @Environment(SessionStore.self) private var session
    @State private var viewModel: TransactionsViewModel?
    @State private var activeSheet: ActiveSheet?

    @State private var toastState = ToastState()
    /// Optimistically hidden while a swipe-delete's undo window is open — see
    /// `TransactionsListView.pendingDeleteIDs`.
    @State private var pendingDeleteIDs: Set<String> = []
    /// Pair groups whose two legs are showing.
    @State private var expandedPairIDs: Set<String> = []

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
                    restClient: authenticatedRESTClient,
                    onDataChanged: onDataChanged
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
        // Pairing runs on every payment row so search never changes which rows pair up
        // (or the total); a group shows when any of its legs matches the search.
        let visibleGroups = viewModel.paymentGroups(reviews: reviews).filter { group in
            // Optimistically hidden during a swipe-delete's undo window.
            !group.transactions.contains { pendingDeleteIDs.contains($0.id) }
                && !TransactionFiltering.apply(
                    group.transactions,
                    searchQuery: searchQuery,
                    categoryName: viewModel.categoryName,
                    ownerName: viewModel.ownerName
                ).isEmpty
        }
        let groupByRepresentative = Dictionary(uniqueKeysWithValues: visibleGroups.map { ($0.representative.id, $0) })
        let dayGroups = TransactionDayGrouping.group(visibleGroups.map(\.representative))

        List {
            Section {
                summaryCard(viewModel: viewModel, reviews: reviews)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if viewModel.transactions.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if visibleGroups.isEmpty {
                Text("No transactions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayGroups) { day in
                    Section {
                        ForEach(day.transactions, id: \.id) { representative in
                            if let group = groupByRepresentative[representative.id] {
                                groupRows(group, viewModel: viewModel)
                            }
                        }
                    } header: {
                        Text(TransactionDayGrouping.headerText(for: day.id, localeIdentifier: localeIdentifier))
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

            case .moveToPeriod(let transaction):
                MoveToPeriodSheet(transaction: transaction, periods: periods, localeIdentifier: localeIdentifier) { period in
                    Task { await viewModel.moveToPeriod(transaction, newPeriodID: period.id) }
                }
            }
        }
    }

    /// A lone payment is the old single row; a pair is one summary row that opens into its
    /// two legs, each still swipeable on its own.
    @ViewBuilder
    private func groupRows(_ group: PaymentPairing.Group, viewModel: TransactionsViewModel) -> some View {
        if group.isPair {
            pairRow(group, viewModel: viewModel)
                .swipeActions(edge: .trailing) {
                    if canMutate {
                        Button {
                            requestToggleExcluded(group, viewModel: viewModel)
                        } label: {
                            Label(group.isExcluded ? "Include" : "Exclude", systemImage: group.isExcluded ? "eye" : "eye.slash")
                        }
                        .tint(.gray)
                        .accessibilityIdentifier("excludePayment_\(group.id)")
                    }
                    if canMutate && !group.transactions.contains(where: \.isPlaidImported) {
                        Button(role: .destructive) {
                            requestDelete(group, viewModel: viewModel)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("deletePayment_\(group.id)")
                    }
                }
            if expandedPairIDs.contains(group.id) {
                ForEach(group.transactions, id: \.id) { leg in
                    legRow(leg, viewModel: viewModel)
                        .swipeActions(edge: .leading) { leadingActions(for: leg) }
                        .swipeActions(edge: .trailing) { trailingActions(for: leg, viewModel: viewModel) }
                }
            }
        } else if let transaction = group.transactions.first {
            row(transaction, viewModel: viewModel)
                .swipeActions(edge: .leading) { leadingActions(for: transaction) }
                .swipeActions(edge: .trailing) { trailingActions(for: transaction, viewModel: viewModel) }
        }
    }

    @ViewBuilder
    private func leadingActions(for transaction: Wellspent_V1_Transaction) -> some View {
        if canEdit {
            Button {
                activeSheet = .editTransaction(transaction)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier("editTransaction_\(transaction.name)")

            if periods.count > 1 {
                Button {
                    activeSheet = .moveToPeriod(transaction)
                } label: {
                    Label("Move to Period", systemImage: "calendar.badge.clock")
                }
                .tint(.teal)
                .accessibilityIdentifier("moveToPeriod_\(transaction.name)")
            }
        }
    }

    @ViewBuilder
    private func trailingActions(for transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
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

    /// One payment, shown once at the amount that left the paying account.
    private func pairRow(_ group: PaymentPairing.Group, viewModel: TransactionsViewModel) -> some View {
        let outflow = group.transactions[0]
        let inflow = group.transactions[1]
        let card = viewModel.paymentMethodName(for: inflow.paymentMethodID)
        let source = viewModel.paymentMethodName(for: outflow.paymentMethodID)
        let isExpanded = expandedPairIDs.contains(group.id)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let card {
                    Text("Payment to \(card)")
                } else {
                    Text("Card payment")
                }
                if let source {
                    HStack(spacing: 4) {
                        ColorDotView(hex: viewModel.paymentMethodColor(for: outflow.paymentMethodID), diameter: 8)
                        Text("From \(source)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(TransactionAmountFormatting.displayText(
                units: outflow.amount.units,
                nanos: outflow.amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
            .foregroundStyle(.red)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(group.isExcluded ? 0.5 : 1)
        .contentShape(Rectangle())
        // A simultaneous gesture, not a Button: a row-spanning Button makes the swipe
        // recognisers wait to rule out a tap (see FixedExpenseRow).
        .simultaneousGesture(TapGesture().onEnded {
            if isExpanded { expandedPairIDs.remove(group.id) } else { expandedPairIDs.insert(group.id) }
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("paymentPair_\(group.id)")
    }

    /// One side of a paired payment: which way the money went, in which account, on which day.
    private func legRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        let isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
        let method = viewModel.paymentMethodName(for: transaction.paymentMethodID) ?? ""
        let date = transaction.date.dateOnly.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguageStore.currentLocale))

        return HStack {
            Image(systemName: isReceived ? "arrow.down.left" : "arrow.up.right")
                .foregroundStyle(isReceived ? .green : .red)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                if isReceived {
                    Text("Into \(method)")
                } else {
                    Text("Out of \(method)")
                }
                Text("\(date) · \(transaction.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(TransactionAmountFormatting.displayText(
                units: transaction.amount.units,
                nanos: transaction.amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
            .foregroundStyle(isReceived ? .green : .red)
        }
        .padding(.leading, 12)
        .opacity(transaction.isExcluded ? 0.5 : 1)
        .accessibilityIdentifier("paymentLeg_\(transaction.id)")
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

    /// Deleting a pair removes both legs together, behind one Undo.
    private func requestDelete(_ group: PaymentPairing.Group, viewModel: TransactionsViewModel) {
        let ids = group.transactions.map(\.id)
        pendingDeleteIDs.formUnion(ids)
        Self.logger.info("staged delete payment pair transactionIDs=\(ids.joined(separator: ","), privacy: .public)")
        let message = String(localized: "Payment deleted", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        toastState.show(
            message,
            onUndo: { pendingDeleteIDs.subtract(ids) },
            onExpire: { Task { for id in ids { await viewModel.delete(id: id) } } }
        )
    }

    /// Excludes or includes both legs so the pair never ends up half-counted.
    private func requestToggleExcluded(_ group: PaymentPairing.Group, viewModel: TransactionsViewModel) {
        let ids = group.transactions.map(\.id)
        let shouldExclude = !group.transactions.allSatisfy(\.isExcluded)
        Task {
            await setExcluded(ids: ids, to: shouldExclude, viewModel: viewModel)
            Self.logger.info("toggled excluded payment pair transactionIDs=\(ids.joined(separator: ","), privacy: .public) isExcluded=\(shouldExclude, privacy: .public)")
            let message = shouldExclude
                ? String(localized: "Payment excluded", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                : String(localized: "Payment included", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
            toastState.show(message, onUndo: {
                Task { await setExcluded(ids: ids, to: !shouldExclude, viewModel: viewModel) }
            })
        }
    }

    private func setExcluded(ids: [String], to excluded: Bool, viewModel: TransactionsViewModel) async {
        for id in ids {
            if let current = viewModel.transactions.first(where: { $0.id == id }), current.isExcluded != excluded {
                await viewModel.toggleExcluded(current)
            }
        }
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
