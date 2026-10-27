import SwiftUI
import WellSpentAPI
import WellSpentREST

struct TransactionsListView: View {
    /// Local to this file, not a `Shared/` enum like `BudgetSection` — this
    /// is UI-local tab state, not a reusable domain concept.
    enum TransactionKind: Hashable {
        case variable
        case fixed
        /// Card payments (system "Payment" category) — carved out of
        /// Variable into their own tab so a transaction panel reader doesn't
        /// have to mentally net them out (issue #76). Loan payments and
        /// transfers use different system categories and stay in Variable.
        case payments
    }

    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client
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
    /// Gated add-transaction trigger (payment-method-required check lives in
    /// `BudgetDetailView.startAddingTransaction`) — called from the Variable
    /// tab's own in-content "+" button (issue #92), which replaces
    /// `BudgetDetailView`'s shared toolbar "+" for that tab specifically.
    /// Fixed/Payments are unaffected — they still use the toolbar button.
    let onRequestAddTransaction: () -> Void

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @Environment(SessionStore.self) private var session
    @State private var viewModel: TransactionsViewModel?
    @State private var editingTransaction: Wellspent_V1_Transaction?
    @State private var markReviewTarget: Wellspent_V1_Transaction?
    @State private var installmentTarget: Wellspent_V1_Transaction?
    @State private var fixedFromTxTarget: Wellspent_V1_Transaction?
    @State private var unsplitTarget: Wellspent_V1_Transaction?
    /// Staged by the swipe-to-delete button below, then confirmed via
    /// `.confirmationDialog` — same shape as `unsplitTarget`/`installmentTarget`,
    /// so a swipe can't delete a transaction outright with no way back. Still
    /// used by the Payments tab only (issue #92 scoped Variable's delete to a
    /// toast+Undo instead — see `pendingDeleteIDs`/`toastState` below).
    @State private var deletingTransaction: Wellspent_V1_Transaction?

    // MARK: Variable tab only (issue #92)

    @State private var toastState = ToastState()
    /// Optimistically hidden while a swipe-delete's undo window is open —
    /// the actual `viewModel.delete(id:)` call only fires once `toastState`'s
    /// toast expires without being undone.
    @State private var pendingDeleteIDs: Set<String> = []
    @State private var variableQuickFilter: VariableQuickFilter = .all
    @State private var isVariableFilterSheetPresented = false
    /// Carried forward from the old shared toolbar filter menu — real,
    /// server-backed filters (`docs/features/transactions-filter-for-spent.md`),
    /// now living in the new Filter sheet instead of a quick-filter chip.
    @State private var variableExceededOnly = false
    @State private var variableExcludedOnly = false
    @State private var recategorizingTransaction: Wellspent_V1_Transaction?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $selectedKind) {
                Text("Variable").tag(TransactionKind.variable)
                Text("Fixed").tag(TransactionKind.fixed)
                Text("Payments").tag(TransactionKind.payments)
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
            case .payments:
                Group {
                    if let viewModel {
                        paymentsContent(viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                }
            case .fixed:
                FixedExpensesListView(
                    budgetPeriodID: budgetPeriodID,
                    budgetProfileID: budgetProfileID,
                    authenticatedRESTClient: authenticatedRESTClient,
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
        // Confirming/dismissing a review in the Review tab mutates
        // `reviewViewModel.reviews` in place, but this view can be mounted
        // off-screen (TabView keeps every tab alive) where SwiftUI doesn't
        // reliably redraw on an Observable change alone — reload explicitly
        // so a confirmed match actually drops out of this list right away.
        .onChange(of: reviewViewModel?.reviews) { _, _ in
            Task { await viewModel?.load() }
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: TransactionsViewModel) -> some View {
        let reviews = reviewViewModel?.reviews ?? []
        let confirmedFiltered = viewModel.visibleTransactions(reviews: reviews)
        let hasPendingMatch: (Wellspent_V1_Transaction) -> Bool = { viewModel.pendingMatchName(for: $0, reviews: reviews) != nil }
        let visibleTransactions = VariableQuickFiltering.apply(
            confirmedFiltered.filter { !pendingDeleteIDs.contains($0.id) },
            filter: variableQuickFilter,
            exceededOnly: variableExceededOnly,
            excludedOnly: variableExcludedOnly,
            searchQuery: searchQuery,
            incomeCategoryID: viewModel.categories.first { $0.isSystem(.income) }?.id,
            overBudgetTransactionIDs: variableExceededOnly ? viewModel.overBudgetTransactionIDs : [],
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName,
            hasPendingMatch: hasPendingMatch
        )
        let dayGroups = TransactionDayGrouping.group(visibleTransactions)
        let needsReviewCount = VariableQuickFiltering.needsReviewCount(confirmedFiltered, categoryName: viewModel.categoryName, hasPendingMatch: hasPendingMatch)

        List {
            Section {
                summaryCard(viewModel: viewModel)
                quickFilterChips(needsReviewCount: needsReviewCount)
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
                            transactionRow(transaction, viewModel: viewModel, reviews: reviews)
                                // Edit lives on a leading (swipe-right) action now,
                                // not a row tap — frees the row itself for a plain
                                // tap gesture (e.g. an expand affordance) later.
                                .swipeActions(edge: .leading) {
                                    leadingSwipeActions(for: transaction)
                                }
                                .swipeActions(edge: .trailing) {
                                    trailingSwipeActions(for: transaction, viewModel: viewModel)
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
                restClient: authenticatedRESTClient
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
                    restClient: authenticatedRESTClient
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
                    authenticatedRESTClient: authenticatedRESTClient
                ) {
                    Task { await reviewViewModel?.load() }
                }
            }
        }
        .confirmationDialog(
            "Undo installment split",
            isPresented: Binding(
                get: { unsplitTarget != nil },
                set: { if !$0 { unsplitTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Undo split", role: .destructive) {
                if let unsplitTarget {
                    Task { await viewModel.deleteInstallmentPlan(unsplitTarget) }
                }
            }
        } message: {
            Text("The plan and its remaining payments will be deleted, and this purchase will count toward its period again.")
        }
        .sheet(isPresented: Binding(
            get: { installmentTarget != nil },
            set: { if !$0 { installmentTarget = nil } }
        )) {
            if let installmentTarget {
                InstallmentPlanSheet(
                    transaction: installmentTarget,
                    budgetPeriodID: budgetPeriodID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    authenticatedRESTClient: authenticatedRESTClient
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { fixedFromTxTarget != nil },
            set: { if !$0 { fixedFromTxTarget = nil } }
        )) {
            if let fixedFromTxTarget {
                CreateFixedFromTransactionSheet(
                    transaction: fixedFromTxTarget,
                    budgetPeriodID: budgetPeriodID,
                    authenticatedRESTClient: authenticatedRESTClient
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
        .sheet(isPresented: $isVariableFilterSheetPresented) {
            variableFilterSheet
        }
        .sheet(isPresented: Binding(
            get: { recategorizingTransaction != nil },
            set: { if !$0 { recategorizingTransaction = nil } }
        )) {
            if let recategorizingTransaction {
                recategorizeSheet(for: recategorizingTransaction, viewModel: viewModel)
            }
        }
    }

    /// "Spent this period" card above the quick-filter chips (issue #92) —
    /// reuses the server-computed totals `TransactionsViewModel` already
    /// carries (`totalText`/`spentProgress`/`remainingSummaryText`); no new
    /// arithmetic lives in this view.
    private func summaryCard(viewModel: TransactionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spent this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if canMutate {
                    Button {
                        onRequestAddTransaction()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("variableAddTransactionButton")
                }
                Button {
                    isVariableFilterSheetPresented = true
                } label: {
                    Image(systemName: (variableExceededOnly || variableExcludedOnly) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("variableFilterButton")
            }
            Text(viewModel.totalText)
                .font(.title2.bold())
                .accessibilityIdentifier("transactionsTotal")
            ProgressView(value: viewModel.spentProgress)
                .tint(.accentColor)
            Text(viewModel.remainingSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityIdentifier("variableSummaryCard")
    }

    private func quickFilterChips(needsReviewCount: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VariableQuickFilter.allCases) { option in
                    Button {
                        variableQuickFilter = option
                    } label: {
                        HStack(spacing: 4) {
                            Text(option.label)
                            if option == .needsReview && needsReviewCount > 0 {
                                Text("\(needsReviewCount)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(variableQuickFilter == option ? Color.primary : Color(.secondarySystemBackground), in: Capsule())
                        .foregroundStyle(variableQuickFilter == option ? Color(.systemBackground) : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("variableQuickFilter_\(option.rawValue)")
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func leadingSwipeActions(for transaction: Wellspent_V1_Transaction) -> some View {
        if canEdit {
            Button {
                editingTransaction = transaction
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier("editTransaction_\(transaction.name)")

            if !transaction.installmentFixedExpenseID.isEmpty {
                Button {
                    unsplitTarget = transaction
                } label: {
                    Label("Undo split", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
                .accessibilityIdentifier("unsplitInstallments_\(transaction.name)")
            } else if InstallmentPlan.canSplit(transaction) {
                Button {
                    installmentTarget = transaction
                } label: {
                    Label("Split into installments", systemImage: "arrow.triangle.branch")
                }
                .tint(.purple)
                .accessibilityIdentifier("splitIntoInstallments_\(transaction.name)")
            }

            if CreateFixedFromTransaction.canCreate(transaction) {
                Button {
                    fixedFromTxTarget = transaction
                } label: {
                    Label("Create a fixed expense", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(.indigo)
                .accessibilityIdentifier("createFixedFromTransaction_\(transaction.name)")
            }
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(for transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        if canEdit {
            Button {
                markReviewTarget = transaction
            } label: {
                Label("Flag for Review", systemImage: "flag")
            }
            .tint(.yellow)
            .accessibilityIdentifier("flagForReview_\(transaction.name)")
        }

        if canMutate {
            Button {
                Task { await viewModel.toggleExcluded(transaction) }
            } label: {
                Label(transaction.isExcluded ? "Include" : "Exclude", systemImage: transaction.isExcluded ? "eye" : "eye.slash")
            }
            .tint(.gray)
            // Re-including a converted purchase would count it alongside
            // the plan built from it.
            .disabled(!transaction.installmentFixedExpenseID.isEmpty)
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

    /// Toast+Undo instead of `.confirmationDialog` for Delete specifically
    /// (issue #92) — the row hides immediately; the real delete only fires
    /// once the toast expires without an Undo tap.
    private func requestDelete(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) {
        pendingDeleteIDs.insert(transaction.id)
        let message = String(localized: "Transaction deleted", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        let id = transaction.id
        toastState.show(
            message,
            onUndo: { pendingDeleteIDs.remove(id) },
            onExpire: { Task { await viewModel.delete(id: id) } }
        )
    }

    /// Carries forward `TransactionFilterOption.exceededOnly`/`.excludedOnly`
    /// — real, server-backed filters (docs/features/transactions-filter-for-spent.md)
    /// — into the Variable tab's own bottom sheet, replacing the toolbar
    /// filter menu for this tab specifically.
    private var variableFilterSheet: some View {
        NavigationStack {
            Form {
                Toggle(TransactionFilterOption.exceededOnly.label, isOn: $variableExceededOnly)
                    .accessibilityIdentifier("variableExceededOnlyToggle")
                Toggle(TransactionFilterOption.excludedOnly.label, isOn: $variableExcludedOnly)
                    .accessibilityIdentifier("variableExcludedOnlyToggle")
                Button("Reset") {
                    variableExceededOnly = false
                    variableExcludedOnly = false
                }
            }
            .sheetChrome(Text("Filters")) { isVariableFilterSheetPresented = false }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isVariableFilterSheetPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Tap-to-recategorize (issue #92) — a lightweight sheet, same `List`
    /// dot+name row shape `ColorDotPickerField` already uses, rather than a
    /// second picker component.
    private func recategorizeSheet(for transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        NavigationStack {
            List(viewModel.categories, id: \.id) { category in
                Button {
                    recategorizingTransaction = nil
                    Task { await viewModel.updateCategory(for: transaction, to: category.id) }
                } label: {
                    HStack {
                        ColorDotView(hex: category.color, diameter: 10)
                        Text(category.displayName)
                        Spacer()
                        if category.id == transaction.categoryID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("recategorizeTransaction_option_\(category.displayName)")
            }
            .sheetChrome(Text("Category")) { recategorizingTransaction = nil }
        }
        .presentationDetents([.medium, .large])
    }

    /// Mirrors `content(viewModel:)`'s shape at the Fixed tab's level of
    /// behavior: search + day-grouping + `excludedOnly` (spentOnly/
    /// exceededOnly aren't meaningful here, and `BudgetDetailView`'s filter
    /// menu never offers them on this tab). No flag-for-review, installment
    /// split, or create-fixed-from-transaction — those are Variable-spend-
    /// specific. See docs for issue #76.
    @ViewBuilder
    private func paymentsContent(viewModel: TransactionsViewModel) -> some View {
        let reviews = reviewViewModel?.reviews ?? []
        let paymentCategoryID = viewModel.categories.first { $0.isSystem(.payment) }?.id ?? 0
        let visibleTransactions = TransactionFiltering.apply(
            viewModel.paymentTransactions(reviews: reviews),
            filter: filter,
            searchQuery: searchQuery,
            incomeCategoryID: viewModel.categories.first { $0.isSystem(.income) }?.id,
            overBudgetTransactionIDs: [],
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName
        )
        let dayGroups = TransactionDayGrouping.group(visibleTransactions)

        List {
            Section {
                LabeledContent("Total", value: viewModel.paymentsTotalText(reviews: reviews))
                    .accessibilityIdentifier("paymentsTotal")
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
                            paymentsRow(transaction, viewModel: viewModel)
                                .swipeActions(edge: .leading) {
                                    if canEdit {
                                        Button {
                                            editingTransaction = transaction
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                        .accessibilityIdentifier("editTransaction_\(transaction.name)")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    if canMutate && !transaction.isPlaidImported {
                                        Button("Delete", role: .destructive) {
                                            deletingTransaction = transaction
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
                defaultCategoryID: paymentCategoryID,
                restClient: authenticatedRESTClient
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
                    restClient: authenticatedRESTClient
                ) { updated in
                    viewModel.replaceTransaction(updated)
                }
            }
        }
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: Binding(
                get: { deletingTransaction != nil },
                set: { if !$0 { deletingTransaction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletingTransaction {
                    Task { await viewModel.delete(id: deletingTransaction.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func paymentsRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
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

    /// Row content for the Variable tab. Every action that used to be an
    /// inline trailing button (flag/split/create-fixed/exclude) now lives in
    /// `leadingSwipeActions`/`trailingSwipeActions` instead (issue #92) — the
    /// only tap target left on the row itself is the category chip.
    private func transactionRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel, reviews: [Wellspent_V1_TransactionReview]) -> some View {
        let isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
        let pendingMatchName = viewModel.pendingMatchName(for: transaction, reviews: reviews)

        let nameContent = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(transaction.name)
                    .foregroundStyle(.primary)
                if let pendingMatchName {
                    Text("(linked to \(pendingMatchName))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Says why the row is excluded — otherwise a converted
                // purchase reads as arbitrarily left out of the totals.
                if !transaction.installmentFixedExpenseID.isEmpty {
                    Text("(installments)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("installmentBadge_\(transaction.name)")
                }
                // Marks a row the app created from last period's ending
                // balance, so it doesn't read as a charge the user forgot
                // making. It stays fully editable — deleting it is how you
                // say you've already settled it.
                if !transaction.carriedFromBudgetPeriodID.isEmpty {
                    Text("(carried over)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("carryoverBadge_\(transaction.name)")
                }
            }
            HStack(spacing: 4) {
                categoryChip(transaction, viewModel: viewModel)
                if let methodName = viewModel.paymentMethodName(for: transaction.paymentMethodID) {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorDotView(hex: viewModel.paymentMethodColor(for: transaction.paymentMethodID), diameter: 8)
                    Text(methodName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        return HStack {
            nameContent
                .accessibilityIdentifier("transactionRow_\(transaction.name)")

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

    /// Tap-to-recategorize chip (issue #92) — reads "Categorize", dashed
    /// border, accent-tinted when uncategorized, matching the design
    /// reference; a solid chip with the real name otherwise.
    private func categoryChip(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        let categoryName = viewModel.categoryName(for: transaction.categoryID)
        return Button {
            recategorizingTransaction = transaction
        } label: {
            HStack(spacing: 3) {
                if let categoryName {
                    ColorDotView(hex: viewModel.categoryColor(for: transaction.categoryID), diameter: 8)
                    Text(categoryName)
                } else {
                    Text("Categorize")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(categoryName == nil ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                Capsule().strokeBorder(categoryName == nil ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 1, dash: categoryName == nil ? [3, 2] : []))
            )
            .foregroundStyle(categoryName == nil ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityIdentifier("recategorizeTransaction_\(transaction.name)")
    }
}

#Preview {
    NavigationStack {
        TransactionsListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            selectedKind: .constant(.variable),
            isAddTransactionPresented: .constant(false),
            isAddFixedExpensePresented: .constant(false),
            isActive: true,
            canEdit: true,
            searchQuery: "",
            filter: .none,
            onRequestAddTransaction: {}
        )
    }
}
