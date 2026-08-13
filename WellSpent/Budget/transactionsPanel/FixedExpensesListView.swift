import SwiftUI
import WellSpentAPI
import os

struct FixedExpensesListView: View {
    private static let logger = AppLogger.logger("FixedExpenses")

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
    /// True when viewing an archived (past) period. Editing a Fixed row's
    /// template (`EditFixedExpenseView`) is deliberately left gated by
    /// `canEdit` alone this phase (see docs/features/budget-list-view-rework.md).
    /// `canMutate` gates delete/mark-paid/unmark/exclude, all fully blocked
    /// when archived. The per-occurrence category-only edit path (when the
    /// row's template is missing/deactivated, or the period is archived) is
    /// `AddEditTransactionView` in its `forceLocked`/`isArchivedPeriod`
    /// mode — see the edit sheet below.
    var isArchivedPeriod: Bool = false
    let searchQuery: String
    let filter: TransactionFilterOption

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @State private var viewModel: FixedExpensesViewModel?
    @State private var editingTransaction: Wellspent_V1_Transaction?
    @State private var markingPaidTransaction: Wellspent_V1_Transaction?
    /// Paid rows are collapsed by default (docs/features/transactions.md) —
    /// no native collapsible `List` `Section` exists in SwiftUI, so this
    /// gates whether the paid day-groups render at all, same manual-toggle
    /// shape `FixedExpenseRow`'s own `isExpanded` already uses one level down.
    @State private var isPaidExpanded = false
    /// Unlike Paid, Future starts expanded: an upcoming bill is something you'd
    /// want to see without a tap, whereas a paid one is already handled.
    @State private var isFutureExpanded = true

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
        // See the matching comment in TransactionsListView — this view can
        // be mounted off-screen inside the TabView, so a confirmed review
        // needs an explicit reload to actually show up in this row's
        // expandable linked-transactions list right away.
        .onChange(of: reviewViewModel?.reviews) { _, _ in
            Task { await viewModel?.load() }
        }
    }

    @ViewBuilder
    private func content(viewModel: FixedExpensesViewModel) -> some View {
        let visibleTransactions = TransactionFiltering.apply(
            viewModel.transactions,
            filter: filter,
            searchQuery: searchQuery,
            incomeCategoryID: viewModel.categories.first { $0.isSystem && $0.name == "Income" }?.id,
            overBudgetTransactionIDs: [],
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName
        )
        // Unpaid (uncollapsed) / Paid (collapsed by default) split — see
        // docs/features/transactions.md. The split happens after filtering
        // so search/filters keep applying uniformly to both sections.
        let unpaidTransactions = visibleTransactions.filter { !$0.isPaid }
        let paidTransactions = visibleTransactions.filter(\.isPaid)
        let unpaidGroups = TransactionDayGrouping.group(unpaidTransactions)
        let paidGroups = TransactionDayGrouping.group(paidTransactions)
        // Upcoming bills — templates with nothing spawned this period. Not
        // day-grouped like the two sections above: these aren't transactions
        // and have no date in this period, so each carries its own next-due
        // date instead. Search/filters don't apply either, since those operate
        // on transaction fields these rows don't have.
        let upcomingExpenses = UpcomingFixedExpenses.notDue(
            expenses: viewModel.fixedExpenses,
            transactions: viewModel.transactions,
            isArchivedPeriod: isArchivedPeriod
        )

        List {
            Section {
                LabeledContent("Total", value: viewModel.totalText)
                    .accessibilityIdentifier("fixedExpensesTotal")
            }

            if viewModel.transactions.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if visibleTransactions.isEmpty && upcomingExpenses.isEmpty {
                // Upcoming templates count as content: a period whose bills are
                // all still ahead of it isn't empty, it's early.
                Text("No fixed expenses yet.")
                    .foregroundStyle(.secondary)
            } else {
                if !unpaidTransactions.isEmpty {
                    Section {
                        Text("Unpaid (\(unpaidTransactions.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(unpaidGroups) { group in
                        dayGroupSection(group, viewModel: viewModel)
                    }
                }

                if !paidTransactions.isEmpty {
                    Section {
                        Button {
                            isPaidExpanded.toggle()
                        } label: {
                            HStack {
                                Text("Paid (\(paidTransactions.count))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: isPaidExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("togglePaidFixedExpenses")
                    }
                    if isPaidExpanded {
                        ForEach(paidGroups) { group in
                            dayGroupSection(group, viewModel: viewModel)
                        }
                    }
                }

                if !upcomingExpenses.isEmpty {
                    Section {
                        Button {
                            isFutureExpanded.toggle()
                        } label: {
                            HStack {
                                Text("Future (\(upcomingExpenses.count))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: isFutureExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("toggleFutureFixedExpenses")
                    }
                    if isFutureExpanded {
                        Section {
                            ForEach(upcomingExpenses, id: \.id) { expense in
                                UpcomingFixedExpenseRow(
                                    expense: expense,
                                    viewModel: viewModel,
                                    currencyCode: currencyCode,
                                    localeIdentifier: localeIdentifier
                                )
                            }
                        }
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
            // `template(for:)` returns nil when the linked FixedExpense is
            // missing or has been deactivated (e.g. a completed payment
            // plan) — previously this silently rendered an empty sheet with
            // no explanation. Falls back to the same category-only locked
            // edit archived/Plaid-imported transactions already use, rather
            // than showing nothing.
            if let editingTransaction {
                if let template = viewModel.template(for: editingTransaction) {
                    EditFixedExpenseView(
                        expense: template,
                        currencyCode: currencyCode,
                        categories: viewModel.categories,
                        paymentMethods: viewModel.paymentMethods,
                        authenticatedClient: authenticatedClient
                    ) { _ in
                        Task { await viewModel.handleTemplateUpdated() }
                    }
                } else {
                    AddEditTransactionView(
                        mode: .edit(editingTransaction),
                        budgetPeriodID: budgetPeriodID,
                        currencyCode: currencyCode,
                        categories: viewModel.categories,
                        paymentMethods: viewModel.paymentMethods,
                        isArchivedPeriod: isArchivedPeriod,
                        forceLocked: true,
                        authenticatedClient: authenticatedClient
                    ) { _ in
                        Task { await viewModel.load() }
                    }
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

    /// Renders one day-group's header + rows — shared by both the Unpaid and
    /// Paid sections so the row/delete logic isn't duplicated between them.
    @ViewBuilder
    private func dayGroupSection(_ group: TransactionDayGrouping.DayGroup, viewModel: FixedExpensesViewModel) -> some View {
        Section {
            ForEach(group.transactions, id: \.id) { transaction in
                FixedExpenseRow(
                    transaction: transaction,
                    viewModel: viewModel,
                    linkedReviews: viewModel.linkedReviews(for: transaction, reviews: reviewViewModel?.reviews ?? []),
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    canEdit: canEdit,
                    canMutate: canMutate,
                    onEdit: {
                        Self.logger.info("edit tapped transactionID=\(transaction.id, privacy: .public) fixedExpenseID=\(transaction.fixedExpenseID, privacy: .public)")
                        editingTransaction = transaction
                    },
                    onMarkPaid: { markingPaidTransaction = transaction }
                )
            }
            .onDelete(perform: canMutate ? { offsets in
                for index in offsets {
                    let transaction = group.transactions[index]
                    Task { await viewModel.delete(transaction) }
                }
            } : nil)
        } header: {
            Text(TransactionDayGrouping.headerText(for: group.id, localeIdentifier: localeIdentifier))
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
    let canMutate: Bool
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

                if canMutate {
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
                    ColorDotView(hex: viewModel.categoryColor(for: transaction.categoryID), diameter: 8)
                    Text(categoryName)
                }
                if let methodName = viewModel.paymentMethodName(for: transaction.paymentMethodID) {
                    Text("·")
                    ColorDotView(hex: viewModel.paymentMethodColor(for: transaction.paymentMethodID), diameter: 8)
                    Text(methodName)
                }
                if let progressText = viewModel.paymentsProgressText(for: transaction) {
                    Text("·")
                    Text(progressText)
                        .accessibilityIdentifier("fixedExpensePaymentsProgress_\(transaction.name)")
                }
                Text("·")
                // `.dateOnly`, not `.date` — see Shared/DateOnly.swift.
                Text(transaction.date.dateOnly.formatted(
                    Date.FormatStyle(locale: Locale(identifier: localeIdentifier)).month(.abbreviated).day()
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// A fixed-expense template that isn't due in this period yet.
///
/// Deliberately inert — no edit, no mark-paid, no swipe-to-delete. There is no
/// transaction to act on: the row exists so an upcoming bill isn't invisible
/// until the period it lands in. Muted for the same reason, so it can't be
/// mistaken for something already owed.
private struct UpcomingFixedExpenseRow: View {
    let expense: Wellspent_V1_FixedExpense
    let viewModel: FixedExpensesViewModel
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(expense.name)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(MoneyFormatting.format(
                    units: expense.plannedAmount.units,
                    nanos: expense.plannedAmount.nanos,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                ))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                let nextDue = UpcomingFixedExpenses.nextDueText(for: expense, localeIdentifier: localeIdentifier)
                if !nextDue.isEmpty {
                    Text("Due \(nextDue)")
                        .accessibilityIdentifier("upcomingFixedExpenseDue_\(expense.name)")
                }
                if let categoryName = viewModel.categoryName(for: expense.categoryID) {
                    if !nextDue.isEmpty { Text("·") }
                    ColorDotView(hex: viewModel.categoryColor(for: expense.categoryID), diameter: 8)
                    Text(categoryName)
                }
                if let methodName = viewModel.paymentMethodName(for: expense.paymentMethodID) {
                    Text("·")
                    Text(methodName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("upcomingFixedExpenseRow_\(expense.name)")
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
            canEdit: true,
            searchQuery: "",
            filter: .none
        )
    }
}
