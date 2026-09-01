import SwiftUI
import WellSpentAPI
import os

struct FixedExpensesListView: View {
    private static let logger = AppLogger.logger("FixedExpenses")

    /// Every locally-triggered sheet on this screen, so only one presentation
    /// modifier drives them. See `activeSheet` for why the add sheet is not
    /// in here.
    private enum ActiveSheet: Identifiable {
        case editTransaction(Wellspent_V1_Transaction)
        case editTemplate(Wellspent_V1_FixedExpense)
        case markPaid(Wellspent_V1_Transaction)

        var id: String {
            switch self {
            case .editTransaction(let transaction): return "editTransaction-\(transaction.id)"
            case .editTemplate(let expense): return "editTemplate-\(expense.id)"
            case .markPaid(let transaction): return "markPaid-\(transaction.id)"
            }
        }
    }

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
    /// One `.sheet(item:)` instead of a `.sheet(isPresented:)` per case:
    /// stacking those on a single view is what caused the Plaid double-tap
    /// bug (v1.25.0). The add sheet stays its own modifier — its binding is
    /// owned by `BudgetDetailView`'s toolbar, and mirroring it in here would
    /// reintroduce the cross-wiring this avoids.
    @State private var activeSheet: ActiveSheet?
    /// Deleting an upcoming template stops a recurring bill for every future
    /// period, so it confirms first — unlike deleting a single transaction.
    @State private var deletingTemplate: Wellspent_V1_FixedExpense?
    /// Staged by the spawned-transaction swipe-to-delete below, same
    /// stage-then-confirm shape as `deletingTemplate` — `.onDelete`'s own
    /// swipe button calls its closure immediately with no way to interpose a
    /// dialog, so the closure only records the target and the actual delete
    /// happens from the confirmation button.
    @State private var deletingTransaction: Wellspent_V1_Transaction?
    /// Paid rows are collapsed by default (docs/features/transactions.md) —
    /// no native collapsible `List` `Section` exists in SwiftUI, so this
    /// gates whether the paid day-groups render at all, same manual-toggle
    /// shape `FixedExpenseRow`'s own `isExpanded` already uses one level down.
    /// Unpaid starts expanded — it's the section you came for — but collapses
    /// so a long list of bills doesn't force a scroll past it to reach Paid or
    /// Future.
    @State private var isUnpaidExpanded = true
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
            incomeCategoryID: viewModel.categories.first { $0.isSystem(.income) }?.id,
            overBudgetTransactionIDs: [],
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName
        )
        // Unpaid (uncollapsed) / Paid (collapsed by default) split — see
        // docs/features/transactions.md. The split happens after filtering
        // so search/filters keep applying uniformly to both sections.
        let unpaidTransactions = visibleTransactions.filter { !$0.isPaid }
        let paidTransactions = visibleTransactions.filter(\.isPaid)
        // Oldest first: this list is a schedule, so the month runs top to
        // bottom. The Variable list keeps the newest-first default.
        let unpaidGroups = TransactionDayGrouping.group(unpaidTransactions, ascending: true)
        let paidGroups = TransactionDayGrouping.group(paidTransactions, ascending: true)
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
                        collapsibleHeader(
                            title: "Unpaid (\(unpaidTransactions.count))",
                            isExpanded: isUnpaidExpanded,
                            identifier: "toggleUnpaidFixedExpenses"
                        ) { isUnpaidExpanded.toggle() }
                    }
                    if isUnpaidExpanded {
                        ForEach(unpaidGroups) { group in
                            dayGroupSection(group, viewModel: viewModel)
                        }
                    }
                }

                if !paidTransactions.isEmpty {
                    Section {
                        collapsibleHeader(
                            title: "Paid (\(paidTransactions.count))",
                            isExpanded: isPaidExpanded,
                            identifier: "togglePaidFixedExpenses"
                        ) { isPaidExpanded.toggle() }
                    }
                    if isPaidExpanded {
                        ForEach(paidGroups) { group in
                            dayGroupSection(group, viewModel: viewModel)
                        }
                    }
                }

                if !upcomingExpenses.isEmpty {
                    Section {
                        collapsibleHeader(
                            title: "Future (\(upcomingExpenses.count))",
                            isExpanded: isFutureExpanded,
                            identifier: "toggleFutureFixedExpenses"
                        ) { isFutureExpanded.toggle() }
                    }
                    if isFutureExpanded {
                        Section {
                            ForEach(upcomingExpenses, id: \.id) { expense in
                                UpcomingFixedExpenseRow(
                                    expense: expense,
                                    viewModel: viewModel,
                                    currencyCode: currencyCode,
                                    localeIdentifier: localeIdentifier,
                                    canEdit: canEdit
                                ) {
                                    Self.logger.info("edit upcoming template tapped fixedExpenseID=\(expense.id, privacy: .public)")
                                    activeSheet = .editTemplate(expense)
                                }
                            }
                            // `canEdit`, not `canMutate`: a template is
                            // profile-level, like categories and payment
                            // methods, so the archived-period rule doesn't
                            // apply — and Future is hidden there anyway.
                            .onDelete(perform: canEdit ? { offsets in
                                guard let index = offsets.first else { return }
                                deletingTemplate = upcomingExpenses[index]
                            } : nil)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editTransaction(let transaction):
                // `template(for:)` returns nil when the linked FixedExpense is
                // missing or has been deactivated (e.g. a completed payment
                // plan) — previously this silently rendered an empty sheet with
                // no explanation. Falls back to the same category-only locked
                // edit archived/Plaid-imported transactions already use, rather
                // than showing nothing.
                if let template = viewModel.template(for: transaction) {
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
                        mode: .edit(transaction),
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

            case .editTemplate(let expense):
                // Straight to the template: an upcoming row has no spawned
                // transaction to resolve one from.
                EditFixedExpenseView(
                    expense: expense,
                    currencyCode: currencyCode,
                    categories: viewModel.categories,
                    paymentMethods: viewModel.paymentMethods,
                    authenticatedClient: authenticatedClient
                ) { _ in
                    Task { await viewModel.handleTemplateUpdated() }
                }

            case .markPaid(let transaction):
                MarkAsPaidView(transaction: transaction, currencyCode: currencyCode) { amount, date in
                    Task { await viewModel.markPaid(transaction, paidAmount: amount, paidAt: date) }
                }
            }
        }
        .confirmationDialog(
            "Delete this upcoming expense?",
            isPresented: Binding(
                get: { deletingTemplate != nil },
                set: { if !$0 { deletingTemplate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletingTemplate {
                    Task { await viewModel.deleteTemplate(deletingTemplate) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will stop appearing in future periods. Expenses already recorded in past periods are kept.")
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
                    Task { await viewModel.delete(deletingTransaction) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    /// One tappable section header with a chevron, shared by Unpaid, Paid and
    /// Future so the three can't drift on styling or on which way the chevron
    /// points. SwiftUI has no collapsible `List` `Section`, so each caller
    /// gates its own content on the matching `@State`.
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
            // Without this, a `Button`'s tap target follows the rendered
            // glyphs of its label (the text characters, the icon) rather than
            // the full row — the `Spacer` in between renders nothing, so it
            // isn't hit-testable on its own, which is what made only the
            // chevron feel reliably tappable.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// Renders one day-group's header + rows — shared by both the Unpaid and
    /// Paid sections so the row/delete logic isn't duplicated between them.
    @ViewBuilder
    private func dayGroupSection(_ group: TransactionDayGrouping.DayGroup, viewModel: FixedExpensesViewModel) -> some View {
        Section {
            ForEach(group.transactions, id: \.id) { transaction in
                let onEdit = {
                    Self.logger.info("edit tapped transactionID=\(transaction.id, privacy: .public) fixedExpenseID=\(transaction.fixedExpenseID, privacy: .public)")
                    activeSheet = .editTransaction(transaction)
                }
                FixedExpenseRow(
                    transaction: transaction,
                    viewModel: viewModel,
                    linkedReviews: viewModel.linkedReviews(for: transaction, reviews: reviewViewModel?.reviews ?? []),
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    canMutate: canMutate,
                    autoUpdatePlannedAmount: viewModel.autoUpdatePlannedAmount,
                    onMarkPaid: { activeSheet = .markPaid(transaction) }
                )
                // Edit lives on a leading (swipe-right) action now, not a row
                // tap — frees the row itself to toggle the linked-transactions
                // chevron on tap instead of requiring a precise tap on the
                // small chevron icon.
                .swipeActions(edge: .leading) {
                    if canEdit {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                        .accessibilityIdentifier("editFixedExpense_\(transaction.name)")
                    }
                }
            }
            .onDelete(perform: canMutate ? { offsets in
                guard let index = offsets.first else { return }
                deletingTransaction = group.transactions[index]
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
    let canMutate: Bool
    /// The budget's auto_update_planned_amount setting — drives the re-plan marker.
    let autoUpdatePlannedAmount: Bool
    let onMarkPaid: () -> Void
    @State private var isRePlanNoticePresented = false

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // A plain HStack with a `.simultaneousGesture` tap, not a
                // `Button` — a `Button` spanning nearly the whole row (via
                // `.contentShape(Rectangle())`) has to be proven NOT a tap
                // before UIKit will commit to this row's `.swipeActions` pan
                // gesture, and that arbitration is exactly what showed up as
                // a ~1s hitch before either swipe direction's reveal
                // animation started (reported after this row picked up
                // `.swipeActions(edge: .leading)` below). `.simultaneousGesture`
                // recognizes independently of — rather than competing
                // exclusively with — the row's swipe/scroll recognizers, so
                // it doesn't block them and isn't blocked by them.
                // `.onTapGesture` (`.gesture(TapGesture())`) was tried first
                // and is NOT a substitute here: on a `List` row that also
                // carries `.swipeActions`, it can lose the same arbitration
                // outright and simply never fire — which is the original bug
                // this row's tap-to-expand was fixed for. `collapsibleHeader`
                // below stays a real `Button`, since section headers aren't
                // swipeable and have nothing to arbitrate against.
                HStack {
                    if !linkedReviews.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("expandFixedExpense_\(transaction.name)")
                    }

                    fixedExpenseNameContent
                        .accessibilityIdentifier("fixedExpenseRow_\(transaction.name)")

                    Spacer()

                    Text(MoneyFormatting.format(
                        units: transaction.amount.units,
                        nanos: transaction.amount.nanos,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    ))
                    .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
                // `Button` gave this row its tap-is-a-button accessibility
                // trait for free; restore it explicitly now that the tap is
                // a plain gesture instead.
                .accessibilityAddTraits(linkedReviews.isEmpty ? [] : .isButton)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        guard !linkedReviews.isEmpty else { return }
                        isExpanded.toggle()
                    }
                )

                if canMutate {
                    Button {
                        if transaction.isPaid && autoUpdatePlannedAmount && !transaction.fixedExpenseID.isEmpty
                            && MoneyFormatting.differs(transaction.amount, transaction.plannedAmount) {
                            // No hover on iOS, so this is a tappable popover
                            // rather than web's tooltip.
                            Button {
                                isRePlanNoticePresented = true
                            } label: {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("rePlanMarker_\(transaction.name)")
                            .popover(isPresented: $isRePlanNoticePresented) {
                                Text("Paid at a different amount than planned. From the next period on, this bill will be planned at what you actually paid.")
                                    .font(.footnote)
                                    .padding()
                                    .frame(maxWidth: 280)
                                    .presentationCompactAdaptation(.popover)
                            }
                        }
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
/// Tapping it edits the template and swiping deletes it, matching web — there
/// is no spawned transaction, so both act on the template directly. Mark-paid
/// is still absent: there is nothing to pay yet. Muted so an upcoming bill
/// can't be mistaken for something already owed.
private struct UpcomingFixedExpenseRow: View {
    let expense: Wellspent_V1_FixedExpense
    let viewModel: FixedExpensesViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Group {
                    if canEdit {
                        Button(action: onEdit) {
                            Text(expense.name)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(expense.name)
                            .foregroundStyle(.secondary)
                    }
                }
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
