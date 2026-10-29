import SwiftUI
import WellSpentAPI
import WellSpentREST
import os

/// The Overview sub-tab's Transactions list — Variable and Fixed merged into
/// one combined, type-identified list (Stage 2 of
/// docs/features/overview-plan-navigation-rework.md, issue #76's Payments
/// carve-out stays separate in its own sibling `PaymentsListView`).
///
/// Unpaid Fixed bills float to a dedicated section at the top — the thing a
/// user most needs to see — and everything else (paid Fixed rows and all
/// Variable rows) interleaves into one day-grouped chronological list below,
/// each row tagged by type (`FixedExpenseRow` vs. the Variable row shape this
/// file already had). `MergedTransactionGrouping` is the pure split/filter
/// logic.
///
/// Supersedes the former standalone `FixedExpensesListView` (deleted) — its
/// Unpaid/Paid/Future sections and summary card don't apply once Fixed rows
/// live here; its row views (`FixedExpenseRow`, `UpcomingFixedExpenseRow`)
/// were extracted into their own files, the latter now used by Plan's Fixed
/// Expenses sub-tab. `FixedExpensesViewModel` itself was deleted (Stage 3) —
/// template management now lives in `FixedExpenseTemplatesViewModel`, Plan's
/// own, smaller view model.
struct TransactionsListView: View {
    private static let logger = AppLogger.logger("Transactions")

    /// Every locally-triggered sheet on this list, so only one presentation
    /// modifier drives its sheets (stacking `.sheet(isPresented:)` modifiers
    /// is what caused the Plaid double-tap bug, v1.25.0). The add sheets stay
    /// their own modifiers — their bindings are owned by `BudgetDetailView`'s
    /// toolbar, and mirroring them in here would reintroduce the cross-wiring
    /// this avoids.
    private enum ActiveSheet: Identifiable {
        case editTransaction(Wellspent_V1_Transaction)
        case markReview(Wellspent_V1_Transaction)
        case installmentPlan(Wellspent_V1_Transaction)
        case createFixedFromTransaction(Wellspent_V1_Transaction)
        case recategorize(Wellspent_V1_Transaction)
        case markPaid(Wellspent_V1_Transaction)
        case matchTransactions(Wellspent_V1_Transaction)

        var id: String {
            switch self {
            case .editTransaction(let transaction): return "editTransaction-\(transaction.id)"
            case .markReview(let transaction): return "markReview-\(transaction.id)"
            case .installmentPlan(let transaction): return "installmentPlan-\(transaction.id)"
            case .createFixedFromTransaction(let transaction): return "createFixedFromTransaction-\(transaction.id)"
            case .recategorize(let transaction): return "recategorize-\(transaction.id)"
            case .markPaid(let transaction): return "markPaid-\(transaction.id)"
            case .matchTransactions(let transaction): return "matchTransactions-\(transaction.id)"
            }
        }
    }

    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client
    let currencyCode: String
    let localeIdentifier: String
    @Binding var isAddTransactionPresented: Bool
    @Binding var isAddFixedExpensePresented: Bool
    /// See `ExpensePlanView.isActive`.
    let isActive: Bool
    /// Owned by `BudgetDetailView` (see `TransactionReviewListView`'s doc
    /// comment) — read here to filter confirmed-review matches out of the
    /// Variable rows and show a pending-match hint/linked sub-row, mirroring
    /// web's `TransactionsPanel.tsx`.
    var reviewViewModel: TransactionReviewViewModel? = nil
    let canEdit: Bool
    /// True when viewing an archived (past) period — see
    /// docs/features/budget-list-view-rework.md. Editing a Variable row's
    /// category stays reachable via `canEdit` alone (see
    /// `AddEditTransactionViewModel`'s `isLocked`); `canMutate` additionally
    /// requires the period not be archived, gating delete/exclude/mark-paid
    /// specifically.
    var isArchivedPeriod: Bool = false
    let searchQuery: String
    /// See `TransactionsViewModel.onDataChanged`.
    var onDataChanged: () -> Void = {}

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @Environment(SessionStore.self) private var session
    @State private var viewModel: TransactionsViewModel?
    @State private var unsplitTarget: Wellspent_V1_Transaction?

    // MARK: Swipe-action toasts (issue #92)

    @State private var toastState = ToastState()
    /// Optimistically hidden while a swipe-delete's undo window is open —
    /// the actual delete call only fires once `toastState`'s toast expires
    /// without being undone.
    @State private var pendingDeleteIDs: Set<String> = []
    /// Real, server-backed filters (`docs/features/transactions-filter-for-spent.md`)
    /// — independent toggle chips in the quick-filter row, so a user can
    /// combine e.g. Money Out with Exceeded only at once. Apply to both
    /// Fixed and Variable rows (type-agnostic) — see
    /// `MergedTransactionGrouping.applyFilters`'s doc comment for why the
    /// quick-filter radio below does not.
    @State private var variableExceededOnly = false
    @State private var variableExcludedOnly = false
    /// All/Money Out/Money In/Needs review — a Variable-only concept
    /// (received/spent sign-flip, pending Plaid match). A Fixed row always
    /// passes this one regardless of which option is active; see
    /// `MergedTransactionGrouping.passesVariableOnlyFilter`.
    @State private var variableQuickFilter: VariableQuickFilter = .all
    @State private var activeSheet: ActiveSheet?
    /// Unpaid Fixed section's collapsed state — expanded by default.
    @State private var isUnpaidExpanded = true
    /// Variable rows with a confirmed match, expanded to show the Fixed bill they settled — collapsed by default (issue #97).
    @State private var expandedMatchedTransactionIDs: Set<String> = []

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
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
            .filter { !pendingDeleteIDs.contains($0.id) }
        let hasPendingMatch: (Wellspent_V1_Transaction) -> Bool = { viewModel.pendingMatchName(for: $0, reviews: reviews) != nil }
        let fixedTypeID = TransactionsViewModel.fixedTypeID

        // Unpaid Fixed floats to the top, always shown (search aside — see
        // below) regardless of the quick-filter chips: it's the thing a user
        // most needs to see, and filtering it away by a Variable-only concept
        // would defeat that. Everything else is subject to the full filter
        // chain before being day-grouped.
        let partition = MergedTransactionGrouping.partition(confirmedFiltered, fixedTypeID: fixedTypeID)
        let searchedUnpaidFixed = partition.unpaidFixed.filter {
            TransactionFiltering.matchesSearch(
                name: $0.name,
                categoryName: viewModel.categoryName(for: $0.categoryID),
                ownerName: viewModel.ownerName(for: $0.paymentMethodID),
                query: searchQuery
            )
        }
        let filteredRest = MergedTransactionGrouping.applyFilters(
            partition.rest,
            fixedTypeID: fixedTypeID,
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
        let dayGroups = TransactionDayGrouping.group(filteredRest)
        // "Needs review" only means something for Variable rows (a Fixed row
        // has no category-missing or pending-match concept of its own) — the
        // chip's badge count is scoped to those.
        let needsReviewCount = VariableQuickFiltering.needsReviewCount(
            confirmedFiltered.filter { $0.transactionTypeID != fixedTypeID },
            categoryName: viewModel.categoryName,
            hasPendingMatch: hasPendingMatch
        )

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
            } else if searchedUnpaidFixed.isEmpty && dayGroups.isEmpty {
                Text("No transactions yet.")
                    .foregroundStyle(.secondary)
            } else {
                if !searchedUnpaidFixed.isEmpty {
                    // Real `header:`, not a bare Section, so the boundary reads like the day groups below.
                    Section {
                        if isUnpaidExpanded {
                            ForEach(searchedUnpaidFixed, id: \.id) { transaction in
                                fixedRow(transaction, viewModel: viewModel)
                            }
                        }
                    } header: {
                        collapsibleHeader(
                            // `Text(String)` skips the catalog, so resolve the translation here.
                            title: String(localized: "Unpaid (\(searchedUnpaidFixed.count))", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale),
                            isExpanded: isUnpaidExpanded,
                            identifier: "toggleUnpaidFixed"
                        ) { isUnpaidExpanded.toggle() }
                    }
                }

                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.transactions, id: \.id) { transaction in
                            if transaction.transactionTypeID == fixedTypeID {
                                fixedRow(transaction, viewModel: viewModel)
                            } else {
                                variableRow(transaction, viewModel: viewModel, reviews: reviews)
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
        .sheet(isPresented: $isAddFixedExpensePresented) {
            AddFixedExpenseView(
                budgetProfileID: budgetProfileID,
                currencyCode: currencyCode,
                categories: viewModel.categories,
                paymentMethods: viewModel.paymentMethods,
                restClient: authenticatedRESTClient
            ) { expense, transaction in
                viewModel.addFromCreate(expense: expense, transaction: transaction)
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
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet, viewModel: viewModel)
        }
    }

    /// Backs this list's own `.sheet(item: $activeSheet)`.
    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet, viewModel: TransactionsViewModel) -> some View {
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

        case .markReview(let transaction):
            MarkForReviewSheet(
                transaction: transaction,
                budgetPeriodID: budgetPeriodID,
                budgetProfileID: budgetProfileID,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                authenticatedRESTClient: authenticatedRESTClient
            ) {
                Task { await reviewViewModel?.load() }
            }

        case .installmentPlan(let transaction):
            InstallmentPlanSheet(
                transaction: transaction,
                budgetPeriodID: budgetPeriodID,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                authenticatedRESTClient: authenticatedRESTClient
            ) {
                Task { await viewModel.load() }
            }

        case .createFixedFromTransaction(let transaction):
            CreateFixedFromTransactionSheet(
                transaction: transaction,
                budgetPeriodID: budgetPeriodID,
                authenticatedRESTClient: authenticatedRESTClient
            ) {
                Task { await viewModel.load() }
            }

        case .recategorize(let transaction):
            recategorizeSheet(for: transaction, viewModel: viewModel)

        case .markPaid(let transaction):
            MarkAsPaidView(transaction: transaction, currencyCode: currencyCode) { amount, date in
                Task {
                    await viewModel.markPaid(transaction, paidAmount: amount, paidAt: date)
                    Self.logger.info("marked paid transactionID=\(transaction.id, privacy: .public)")
                    let message = String(localized: "Marked as paid", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                    toastState.show(message, onUndo: {
                        Task {
                            await viewModel.unmark(transaction)
                            await reviewViewModel?.load()
                        }
                    })
                }
            }

        case .matchTransactions(let transaction):
            MatchTransactionsSheet(
                matchedTransaction: transaction,
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

    /// Tappable section header with a chevron, same shape the deleted `FixedExpensesListView` used.
    private func collapsibleHeader(
        title: String,
        isExpanded: Bool,
        identifier: String,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // `Spacer` renders nothing, so the gap wouldn't be tappable without this.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// "Spent this period" card above the quick-filter chips — now covers both Fixed and Variable.
    private func summaryCard(viewModel: TransactionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spent this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.totalText)
                .font(.title2.bold())
                .accessibilityIdentifier("transactionsTotal")
            ProgressView(value: viewModel.spentProgress)
                .tint(viewModel.isOverBudget ? .red : .accentColor)
            Text(viewModel.remainingSummaryText)
                .font(.caption)
                .foregroundStyle(viewModel.isOverBudget ? .red : .secondary)
            if let expectedSavedText = viewModel.expectedSavedText {
                Text(expectedSavedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transactionsExpectedSaved")
            }
            if let actualSavedText = viewModel.actualSavedText {
                Text(actualSavedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transactionsActualSaved")
            }
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

                quickFilterToggleChip(
                    label: TransactionFilterOption.exceededOnly.label,
                    isOn: $variableExceededOnly,
                    identifier: "variableExceededOnlyChip"
                )
                quickFilterToggleChip(
                    label: TransactionFilterOption.excludedOnly.label,
                    isOn: $variableExcludedOnly,
                    identifier: "variableExcludedOnlyChip"
                )
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
    }

    /// "Exceeded only"/"Excluded only" — independent toggle chips (issue
    /// #92 follow-up), visually identical to the `VariableQuickFilter`
    /// chips above but not part of that radio group: tapping one just
    /// flips its own boolean, so it can combine freely with whichever quick
    /// filter is active. Apply to Fixed rows too — see
    /// `MergedTransactionGrouping.applyFilters`.
    private func quickFilterToggleChip(label: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? Color.primary : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(isOn.wrappedValue ? Color(.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Variable row

    @ViewBuilder
    private func leadingSwipeActions(for transaction: Wellspent_V1_Transaction) -> some View {
        if canEdit {
            Button {
                activeSheet = .editTransaction(transaction)
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
                    activeSheet = .installmentPlan(transaction)
                } label: {
                    Label("Split into installments", systemImage: "arrow.triangle.branch")
                }
                .tint(.purple)
                .accessibilityIdentifier("splitIntoInstallments_\(transaction.name)")
            }

            if CreateFixedFromTransaction.canCreate(transaction) {
                Button {
                    activeSheet = .createFixedFromTransaction(transaction)
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
                activeSheet = .markReview(transaction)
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
    /// once the toast expires without an Undo tap. `PaymentsListView` has its
    /// own identical copy (separate `TransactionsViewModel` instance now).
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

    /// Tap-to-recategorize (issue #92) — a lightweight sheet, same `List`
    /// dot+name row shape `ColorDotPickerField` already uses, rather than a
    /// second picker component.
    private func recategorizeSheet(for transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        NavigationStack {
            List(viewModel.categories, id: \.id) { category in
                Button {
                    activeSheet = nil
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
            .sheetChrome(Text("Category")) { activeSheet = nil }
        }
        .presentationDetents([.medium, .large])
    }

    /// Row content for a Variable transaction. Every action that used to be
    /// an inline trailing button (flag/split/create-fixed/exclude) lives in
    /// `leadingSwipeActions`/`trailingSwipeActions` instead (issue #92) — the
    /// only tap target left on the row itself is the category chip.
    private func variableRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel, reviews: [Wellspent_V1_TransactionReview]) -> some View {
        let isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)
        let pendingMatchName = viewModel.pendingMatchName(for: transaction, reviews: reviews)
        let matchedFixed = viewModel.matchedFixedTransaction(for: transaction, reviews: reviews)
        let isExpanded = expandedMatchedTransactionIDs.contains(transaction.id)

        let nameContent = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if matchedFixed != nil {
                    Button {
                        if isExpanded {
                            expandedMatchedTransactionIDs.remove(transaction.id)
                        } else {
                            expandedMatchedTransactionIDs.insert(transaction.id)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("expandMatchedFixed_\(transaction.name)")
                }
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

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
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

            // The Fixed bill this transaction settled, with its original
            // planned amount — read-only context; editing the template
            // still lives in Plan's Fixed Expenses tab (issue #97).
            if isExpanded, let matchedFixed {
                HStack {
                    Text(matchedFixed.name)
                        .font(.caption)
                    Spacer()
                    Text(MoneyFormatting.format(
                        units: matchedFixed.plannedAmount.units,
                        nanos: matchedFixed.plannedAmount.nanos,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, 20)
                .padding(.top, 6)
                .accessibilityIdentifier("matchedFixedExpense_\(transaction.name)")
            }
        }
        .swipeActions(edge: .leading) {
            leadingSwipeActions(for: transaction)
        }
        .swipeActions(edge: .trailing) {
            trailingSwipeActions(for: transaction, viewModel: viewModel)
        }
    }

    /// Tap-to-recategorize chip (issue #92) — reads "Categorize", dashed
    /// border, accent-tinted when uncategorized, matching the design
    /// reference; a solid chip with the real name otherwise.
    private func categoryChip(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        let categoryName = viewModel.categoryName(for: transaction.categoryID)
        return Button {
            activeSheet = .recategorize(transaction)
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

    // MARK: Fixed row

    /// A Fixed row's occurrence-only actions: Mark Paid/Unmark (leading),
    /// Match Transactions/Exclude/Delete-this-occurrence (trailing). There is
    /// deliberately no "Edit" action here — editing the underlying recurring
    /// template is reached only from Plan's Fixed Expenses sub-tab, not this
    /// merged list.
    private func fixedRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        FixedExpenseRow(
            transaction: transaction,
            viewModel: viewModel,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            canMutate: canMutate,
            autoUpdatePlannedAmount: viewModel.autoUpdatePlannedAmount
        )
        .swipeActions(edge: .leading) {
            fixedLeadingSwipeActions(for: transaction, viewModel: viewModel)
        }
        .swipeActions(edge: .trailing) {
            fixedTrailingSwipeActions(for: transaction, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func fixedLeadingSwipeActions(for transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        if canMutate {
            if transaction.isPaid {
                // No mockup analog for an "unmark" action — deliberately not
                // toast+Undo'd: the only real "undo" of an unmark is
                // re-entering the paid amount/date in `MarkAsPaidView`, which
                // a toast button can't supply.
                Button {
                    Self.logger.info("unmark paid tapped transactionID=\(transaction.id, privacy: .public)")
                    Task {
                        await viewModel.unmark(transaction)
                        await reviewViewModel?.load()
                    }
                } label: {
                    Label("Unmark as Paid", systemImage: "xmark.circle")
                }
                .tint(.gray)
                .accessibilityIdentifier("unmarkPaid_\(transaction.name)")
            } else {
                Button {
                    activeSheet = .markPaid(transaction)
                } label: {
                    Label("Mark as Paid", systemImage: "checkmark.circle")
                }
                .tint(.green)
                .accessibilityIdentifier("markPaid_\(transaction.name)")
            }
        }
    }

    @ViewBuilder
    private func fixedTrailingSwipeActions(for transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        if canMutate && !transaction.isPaid {
            Button {
                activeSheet = .matchTransactions(transaction)
            } label: {
                Label("Match Transactions", systemImage: "link.badge.plus")
            }
            .tint(.indigo)
            .accessibilityIdentifier("matchTransactions_\(transaction.name)")
        }

        if canMutate {
            Button {
                requestToggleExcludedFixed(transaction, viewModel: viewModel)
            } label: {
                Label(transaction.isExcluded ? "Include" : "Exclude", systemImage: transaction.isExcluded ? "eye" : "eye.slash")
            }
            .tint(.gray)
            .accessibilityIdentifier("excludeFixedExpense_\(transaction.name)")

            Button(role: .destructive) {
                requestDeleteFixed(transaction, viewModel: viewModel)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteTransaction_\(transaction.name)")
        }
    }

    /// Mirrors `requestDelete` above, calling the Fixed-row deactivate-the-
    /// template delete instead of the plain Variable one.
    private func requestDeleteFixed(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) {
        pendingDeleteIDs.insert(transaction.id)
        Self.logger.info("staged delete transactionID=\(transaction.id, privacy: .public) fixedExpenseID=\(transaction.fixedExpenseID, privacy: .public)")
        let message = String(localized: "Transaction deleted", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        let id = transaction.id
        toastState.show(
            message,
            onUndo: { pendingDeleteIDs.remove(id) },
            onExpire: { Task { await viewModel.delete(transaction) } }
        )
    }

    /// Mirrors `TransactionsListView`'s former `requestToggleExcluded` for
    /// Fixed rows — re-reads the now-updated row for the undo closure rather
    /// than reusing the stale snapshot, which would otherwise re-apply the
    /// same flip instead of reversing it.
    private func requestToggleExcludedFixed(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) {
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
        TransactionsListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            isAddTransactionPresented: .constant(false),
            isAddFixedExpensePresented: .constant(false),
            isActive: true,
            canEdit: true,
            searchQuery: ""
        )
    }
}
