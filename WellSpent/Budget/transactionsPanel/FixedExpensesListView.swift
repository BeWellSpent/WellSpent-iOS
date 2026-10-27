import SwiftUI
import WellSpentAPI
import WellSpentREST
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
        case matchTransactions(Wellspent_V1_Transaction)

        var id: String {
            switch self {
            case .editTransaction(let transaction): return "editTransaction-\(transaction.id)"
            case .editTemplate(let expense): return "editTemplate-\(expense.id)"
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

    private var canMutate: Bool { canEdit && !isArchivedPeriod }

    @Environment(SessionStore.self) private var session
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
    // MARK: Spawned-transaction swipe actions (issue #92)

    @State private var toastState = ToastState()
    /// Optimistically hidden while a swipe-delete's undo window is open — the
    /// actual `viewModel.delete(_:)` call only fires once `toastState`'s
    /// toast expires without being undone. Mirrors `TransactionsListView`'s
    /// identically-named property for the Variable tab.
    @State private var pendingDeleteIDs: Set<String> = []
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
            searchQuery: searchQuery,
            categoryName: viewModel.categoryName,
            ownerName: viewModel.ownerName
        )
        // Optimistically hidden during a swipe-delete's undo window — see
        // `pendingDeleteIDs`.
        .filter { !pendingDeleteIDs.contains($0.id) }
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
                summaryCard(viewModel: viewModel, unpaidCount: unpaidTransactions.count, paidCount: paidTransactions.count)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

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
                restClient: authenticatedRESTClient
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
                        remainingBalance: viewModel.remainingBalance(for: template.id),
                        restClient: authenticatedRESTClient
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
                        restClient: authenticatedRESTClient
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
                    remainingBalance: viewModel.remainingBalance(for: expense.id),
                    restClient: authenticatedRESTClient
                ) { _ in
                    Task { await viewModel.handleTemplateUpdated() }
                }

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
        .toastOverlay(toastState)
    }

    /// "Fixed expenses this period" card (issue #92) — reuses the
    /// server-computed `totalText` already backing the old plain "Total"
    /// row; the unpaid/paid counts are the already-computed section sizes.
    private func summaryCard(viewModel: FixedExpensesViewModel, unpaidCount: Int, paidCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fixed expenses this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.totalText)
                .font(.title2.bold())
                .accessibilityIdentifier("fixedExpensesTotal")
            Text("\(unpaidCount) unpaid · \(paidCount) paid")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityIdentifier("fixedSummaryCard")
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
    /// Paid sections so the row/swipe-action logic isn't duplicated between
    /// them.
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
                    canMutate: canMutate,
                    autoUpdatePlannedAmount: viewModel.autoUpdatePlannedAmount
                )
                // Edit lives on a leading (swipe-right) action, same as the
                // Variable tab's redesign (issue #92); mark-paid/unmark join
                // it there too now, instead of a row-inline checkmark button.
                .swipeActions(edge: .leading) {
                    leadingSwipeActions(for: transaction, viewModel: viewModel)
                }
                .swipeActions(edge: .trailing) {
                    trailingSwipeActions(for: transaction, viewModel: viewModel)
                }
            }
        } header: {
            Text(TransactionDayGrouping.headerText(for: group.id, localeIdentifier: localeIdentifier))
        }
    }

    @ViewBuilder
    private func leadingSwipeActions(for transaction: Wellspent_V1_Transaction, viewModel: FixedExpensesViewModel) -> some View {
        if canEdit {
            Button {
                Self.logger.info("edit tapped transactionID=\(transaction.id, privacy: .public) fixedExpenseID=\(transaction.fixedExpenseID, privacy: .public)")
                activeSheet = .editTransaction(transaction)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier("editFixedExpense_\(transaction.name)")
        }

        if canMutate {
            if transaction.isPaid {
                // No mockup analog for an "unmark" action — this mirrors the
                // row's own former checkmark-toggle behavior, now reached by
                // swipe instead of a tap. Deliberately not toast+Undo'd: the
                // only real "undo" of an unmark is re-entering the paid
                // amount/date in `MarkAsPaidView`, which a toast button can't
                // supply, so this stays the plain, immediate action it always
                // was.
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
    private func trailingSwipeActions(for transaction: Wellspent_V1_Transaction, viewModel: FixedExpensesViewModel) -> some View {
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
                requestToggleExcluded(transaction, viewModel: viewModel)
            } label: {
                Label(transaction.isExcluded ? "Include" : "Exclude", systemImage: transaction.isExcluded ? "eye" : "eye.slash")
            }
            .tint(.gray)
            .accessibilityIdentifier("excludeFixedExpense_\(transaction.name)")

            Button(role: .destructive) {
                requestDelete(transaction, viewModel: viewModel)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteTransaction_\(transaction.name)")
        }
    }

    /// Toast+Undo instead of `.confirmationDialog` for deleting a spawned
    /// transaction (issue #92) — the row hides immediately; the real delete
    /// (which deactivates the whole template, per `viewModel.delete(_:)`)
    /// only fires once the toast expires without an Undo tap. Mirrors
    /// `TransactionsListView.requestDelete`.
    private func requestDelete(_ transaction: Wellspent_V1_Transaction, viewModel: FixedExpensesViewModel) {
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

    /// Toast+Undo for Exclude/Include (issue #92) — `viewModel.toggleExcluded`
    /// flips relative to whatever `isExcluded` the passed transaction
    /// currently carries, so the undo call re-reads the now-updated row from
    /// `viewModel.transactions` rather than reusing the stale snapshot, which
    /// would otherwise re-apply the same flip instead of reversing it.
    private func requestToggleExcluded(_ transaction: Wellspent_V1_Transaction, viewModel: FixedExpensesViewModel) {
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
    @State private var isRePlanNoticePresented = false

    @State private var isExpanded = false

    /// Paid at a different amount than planned, with the setting on that
    /// would carry the real amount into future periods — see
    /// `rePlanMarker`'s doc comment for why this stays its own inline
    /// affordance rather than a swipe action.
    private var showsRePlanNotice: Bool {
        transaction.isPaid && autoUpdatePlannedAmount && !transaction.fixedExpenseID.isEmpty
            && MoneyFormatting.differs(transaction.amount, transaction.plannedAmount)
    }

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

                    // Informational, not a mutation, so it stays its own
                    // inline affordance rather than joining mark-paid/match/
                    // exclude/delete on a swipe action (issue #92). This was
                    // previously nested inside the mark-paid button's own
                    // `action` closure — a plain `() -> Void` closure, not a
                    // `ViewBuilder` — so constructing a `Button` there built
                    // and immediately discarded a value that was never
                    // actually part of the view hierarchy; the popover could
                    // never have shown. Moving it here as a real sibling view
                    // is what the "own small inline affordance" framing
                    // calls for, and incidentally is what makes it render.
                    if canMutate && showsRePlanNotice {
                        rePlanMarker
                    }

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

    /// No hover on iOS, so this is a tappable popover rather than web's
    /// tooltip.
    private var rePlanMarker: some View {
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

    private var fixedExpenseNameContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(transaction.name)
                    .foregroundStyle(.primary)
                // The payment that settled the plan's remaining balance
                // early — the template deactivates and disappears from
                // `listFixedExpenses`, so this is its only lasting record.
                if viewModel.isPaidOffEarly(transaction) {
                    Text("(paid off early)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("paidOffEarlyBadge_\(transaction.name)")
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
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            isAddSheetPresented: .constant(false),
            isActive: true,
            canEdit: true,
            searchQuery: ""
        )
    }
}
