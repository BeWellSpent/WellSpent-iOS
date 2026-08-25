import Foundation
import SwiftUI
import WellSpentAPI

/// Adaptive navigation shell for a budget: a bottom tab bar on iPhone
/// (`.compact` horizontal size class), a `NavigationSplitView` sidebar on
/// iPad (`.regular`). Plan (allocations, 2C-1), Transactions (Variable +
/// Fixed, 2B-2/2B-3), and Manage (People/Income/Categories/Payment Methods,
/// 2A/2B-1) are all real. Expense Overview (actual vs. planned) lands in
/// 2C-2.
///
/// This is the app's home screen (issue #60) — `BudgetHomeView` renders it
/// directly inside a `NavigationStack`. It nests its own per-tab `NavigationStack`s
/// inside a `TabView` (`tabView`/`splitView`) so each tab keeps independent
/// push state. That nesting means the *outer* stack owns the only nav bar
/// that's actually rendered: `.toolbar` items from an inner stack surface
/// only transiently (visible during the push-in transition, then dropped),
/// and `.navigationTitle` from an inner stack never surfaces at all. So all
/// title/toolbar content lives here, driven by `selectedSection` and the
/// per-tab sub-state below, rather than on `ExpensePlanView` /
/// `TransactionsListView` / `FixedExpensesListView` / `BudgetManageView`
/// themselves (which still declare their own for canvas-preview accuracy in
/// isolation, but those never render in the real, nested app).
struct BudgetDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SessionStore.self) private var session
    private let authenticatedClient: ProtocolClient?
    private let currencyCode: String
    private let localeIdentifier: String
    private let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    private let onUserUpdated: (Wellspent_V1_User) -> Void
    private let onDeleted: () -> Void

    @State private var viewModel: BudgetDetailViewModel?
    @State private var selectedSection: BudgetSection = .plan
    @State private var notificationViewModel: NotificationBellViewModel?
    @State private var reviewViewModel: TransactionReviewViewModel?

    @State private var planSelectedKind: ExpensePlanView.PlanKind = .overview
    @State private var transactionsSelectedKind: TransactionsListView.TransactionKind = .variable
    @State private var transactionsSearchQuery = ""
    @State private var transactionsFilter: TransactionFilterOption = .none
    @State private var isAddCategoryPresented = false
    @State private var isAddTransactionPresented = false
    @State private var isAddFixedExpensePresented = false
    @State private var isMenuOpen = false
    @State private var menuDestination: BudgetMenuDestination?
    @State private var isPaymentMethodRequiredPresented = false
    @State private var isPaymentMethodsPresented = false

    init(
        profile: Wellspent_V1_BudgetProfile,
        periodID: String? = nil,
        authenticatedClient: ProtocolClient?,
        currencyCode: String,
        localeIdentifier: String,
        onUpdated: @escaping (Wellspent_V1_BudgetProfile) -> Void,
        onUserUpdated: @escaping (Wellspent_V1_User) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.authenticatedClient = authenticatedClient
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.onUpdated = onUpdated
        self.onUserUpdated = onUserUpdated
        self.onDeleted = onDeleted
        _viewModel = State(initialValue: authenticatedClient.map {
            BudgetDetailViewModel(profile: profile, overridePeriodID: periodID, authenticatedClient: $0)
        })
    }

    var body: some View {
        SideDrawer(isOpen: $isMenuOpen) {
            if let viewModel {
                BudgetMenuDrawer(
                    viewModel: viewModel,
                    localeIdentifier: localeIdentifier,
                    onSelect: { destination in
                        closeMenu()
                        menuDestination = destination
                    },
                    onSelectPeriod: { id in
                        viewModel.selectPeriod(id: id)
                        closeMenu()
                    },
                    onClose: closeMenu
                )
            }
        } content: {
            content
        }
        .navigationTitle(selectedSection.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    private func closeMenu() {
        withAnimation(.snappy(duration: 0.28)) { isMenuOpen = false }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if viewModel?.isArchivedPeriod == true {
                archivedPeriodBanner
            }
            Group {
                if let viewModel {
                    if horizontalSizeClass == .regular {
                        splitView(viewModel: viewModel)
                    } else {
                        tabView(viewModel: viewModel)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .onChange(of: transactionsSelectedKind) { _, _ in
            // Switching Variable <-> Fixed resets the filter rather than
            // silently carrying over an option the other tab doesn't offer.
            transactionsFilter = .none
        }
        .task {
            // Hoisted up from BudgetManageView so the Transactions tab has
            // `currentPeriod.id` (needed for `budget_period_id`) available
            // regardless of which tab is initially selected, not only once
            // the user happens to open Manage.
            await viewModel?.loadPeriod()
        }
        .task {
            await viewModel?.loadRole(currentUserID: session.userID)
        }
        .task {
            // Needed by the toolbar's "+" gate, which is visible before
            // either transaction list mounts and loads its own copy.
            await viewModel?.loadPaymentMethods()
        }
        .sheet(item: $menuDestination) { destination in
            menuDestinationView(destination)
        }
        .alert("Add a payment method first", isPresented: $isPaymentMethodRequiredPresented) {
            Button("Add a payment method") { isPaymentMethodsPresented = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Transactions need a payment method — cash, a card, or a bank account — so you can see where the money went. Add one and you'll be able to record transactions right away.")
        }
        .sheet(isPresented: $isPaymentMethodsPresented) {
            // Presented here rather than switching to the Manage tab and
            // pushing: dismissing lands the user back on Transactions, ready
            // to add the thing they came for.
            if let authenticatedClient, let viewModel {
                NavigationStack {
                    PaymentMethodsListView(
                        budgetProfileID: viewModel.profile.id,
                        authenticatedClient: authenticatedClient,
                        canEdit: viewModel.canEdit
                    )
                }
            }
        }
        .onChange(of: isPaymentMethodsPresented) { _, isPresented in
            if !isPresented {
                Task { await viewModel?.loadPaymentMethods() }
            }
        }
        .task {
            // Created once and polled for the lifetime of this screen (not
            // per-toolbar-appearance) — every tab's bell shares this same
            // instance, so switching tabs never restarts the 30s poll loop.
            guard let authenticatedClient, let viewModel else { return }
            if notificationViewModel == nil {
                notificationViewModel = NotificationBellViewModel(
                    budgetProfileID: viewModel.profile.id,
                    authenticatedClient: authenticatedClient
                )
            }
            await notificationViewModel?.pollUnreadCount()
        }
        .task {
            // Created once here (not inside `TransactionReviewListView`) so
            // the pending count backs the Review tab's badge — same reasoning
            // as `notificationViewModel`. Polled (not a one-shot load) so the
            // badge — visible from every tab — updates without the user
            // having to enter the Review tab first.
            guard let authenticatedClient, let viewModel else { return }
            if reviewViewModel == nil {
                reviewViewModel = TransactionReviewViewModel(
                    budgetProfileID: viewModel.profile.id,
                    authenticatedClient: authenticatedClient
                )
            }
            await reviewViewModel?.pollPendingCount()
        }
    }

    /// Both Fixed and Variable require a payment method to submit, so with
    /// none the form would open, fill in, and refuse to save with nothing
    /// explaining why. Explain up front instead.
    private func startAddingTransaction(_ present: () -> Void) {
        if viewModel?.needsPaymentMethodSetup == true {
            isPaymentMethodRequiredPresented = true
            return
        }
        present()
    }

    /// Shown above the tab content, regardless of which tab is selected —
    /// mirrors web's `BudgetView.tsx` banner placement.
    private var archivedPeriodBanner: some View {
        Label {
            Text("You're viewing a past period. Adding, deleting, marking paid, and excluding transactions are disabled — you can still change a transaction's category.")
                .font(.caption)
        } icon: {
            Image(systemName: "info.circle")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .accessibilityIdentifier("archivedPeriodBanner")
    }

    private func tabView(viewModel: BudgetDetailViewModel) -> some View {
        TabView(selection: $selectedSection) {
            NavigationStack {
                planContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.plan.title, systemImage: BudgetSection.plan.systemImage) }
            .tag(BudgetSection.plan)

            NavigationStack {
                transactionsContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.transactions.title, systemImage: BudgetSection.transactions.systemImage) }
            .tag(BudgetSection.transactions)

            NavigationStack {
                reviewContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.review.title, systemImage: BudgetSection.review.systemImage) }
            .tag(BudgetSection.review)
            .badge(reviewViewModel?.pendingReviews.count ?? 0)

            NavigationStack {
                reportsContent
            }
            .tabItem { Label(BudgetSection.reports.title, systemImage: BudgetSection.reports.systemImage) }
            .tag(BudgetSection.reports)
        }
    }

    /// Tracks `selectedSection` to reproduce each tab's primary action (plus
    /// the ☰ and the bell, common to every tab) at the one level that
    /// actually renders — see the type-level doc comment.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        let canEdit = viewModel?.canEdit ?? true
        // Everything infrequent lives behind this: period switching, the
        // manage panels, settings, help, logging out. Leading placement so
        // it reads as "where am I" rather than "act on this screen", which
        // is what the trailing side is for.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { isMenuOpen = true }
            } label: {
                Image(systemName: "line.3.horizontal")
            }
            .accessibilityIdentifier("budgetMenuButton")
        }
        // Creating a new transaction is fully blocked on an archived period
        // (see docs/features/budget-list-view-rework.md) — Plan additions
        // (expense allocations) are profile-level, not period-level, so
        // they're unaffected and stay gated by role alone.
        let canAddTransaction = canEdit && viewModel?.isArchivedPeriod != true
        switch selectedSection {
        case .plan:
            if canEdit && planSelectedKind == .plan {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddCategoryPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addPlanCategoryButton")
                }
            }
        case .transactions:
            if canAddTransaction && transactionsSelectedKind == .variable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startAddingTransaction { isAddTransactionPresented = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addTransactionButton")
                }
            } else if canAddTransaction {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startAddingTransaction { isAddFixedExpensePresented = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addFixedExpenseButton")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // `Menu` + inline `Picker`, not `.pickerStyle(.menu)`: a
                // menu-style `Picker` ignores this `Image` label and renders
                // the selected title instead ("Todas las transacciones"),
                // which pushed the + and bell into an empty overflow menu.
                // Inline `Picker` still draws the selection checkmark.
                Menu {
                    Picker(selection: $transactionsFilter) {
                        Text(TransactionFilterOption.none.label).tag(TransactionFilterOption.none)
                        if transactionsSelectedKind == .variable {
                            Text(TransactionFilterOption.spentOnly.label).tag(TransactionFilterOption.spentOnly)
                            Text(TransactionFilterOption.exceededOnly.label).tag(TransactionFilterOption.exceededOnly)
                        }
                        Text(TransactionFilterOption.excludedOnly.label).tag(TransactionFilterOption.excludedOnly)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: transactionsFilter == .none ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("transactionsFilterMenu")
            }
        case .review, .reports:
            ToolbarItemGroup {}
        }
        ToolbarItem(placement: .topBarTrailing) {
            NotificationBellButton(viewModel: notificationViewModel)
        }
    }

    /// `List(selection:)` on iOS requires an optional-selection binding (the
    /// non-optional overload is macOS/tvOS-only) — `selectedSection` itself
    /// stays non-optional since `TabView`'s selection doesn't have that
    /// restriction, so the sidebar gets its own optional-wrapped binding.
    private var sidebarSelection: Binding<BudgetSection?> {
        Binding(
            get: { selectedSection },
            set: { if let newValue = $0 { selectedSection = newValue } }
        )
    }

    private func splitView(viewModel: BudgetDetailViewModel) -> some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(BudgetSection.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.systemImage).tag(section)
                }
            }
        } detail: {
            switch selectedSection {
            case .plan:
                NavigationStack {
                    planContent(viewModel: viewModel)
                }
            case .transactions:
                NavigationStack {
                    transactionsContent(viewModel: viewModel)
                }
            case .review:
                NavigationStack {
                    reviewContent(viewModel: viewModel)
                }
            case .reports:
                NavigationStack {
                    reportsContent
                }
            }
        }
    }

    @ViewBuilder
    private func planContent(viewModel: BudgetDetailViewModel) -> some View {
        if let authenticatedClient, let period = viewModel.currentPeriod, !period.id.isEmpty {
            ExpensePlanView(
                budgetPeriodID: period.id,
                budgetProfileID: viewModel.profile.id,
                authenticatedClient: authenticatedClient,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                selectedKind: $planSelectedKind,
                isAddCategoryPresented: $isAddCategoryPresented,
                isActive: selectedSection == .plan,
                canEdit: viewModel.canEdit
            )
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func transactionsContent(viewModel: BudgetDetailViewModel) -> some View {
        VStack(spacing: 0) {
            // A plain in-content field, not SwiftUI's native `.searchable`
            // (tried first, both at this outer level and on the tab's own
            // inner NavigationStack — confirmed dead both times via a live
            // UI test with a full accessibility-hierarchy dump: no search
            // bar element ever installs at all, in either position, on this
            // screen's doubly-nested NavigationStack architecture — an
            // already-pushed destination that itself hosts a TabView whose
            // tabs each wrap their own NavigationStack, per the type-level
            // doc comment's "only one nav bar actually renders" finding).
            // A regular `TextField` sidesteps the whole question of which
            // NavigationStack should host the search chrome, and matches
            // what web's `TransactionsPanel.tsx` actually does — a plain
            // always-visible field, not native OS search UI.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name, category, or owner", text: $transactionsSearchQuery)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("transactionsSearchField")
                if !transactionsSearchQuery.isEmpty {
                    Button {
                        transactionsSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clearTransactionsSearchButton")
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 8)

            if let authenticatedClient, let period = viewModel.currentPeriod, !period.id.isEmpty {
                TransactionsListView(
                    budgetPeriodID: period.id,
                    budgetProfileID: viewModel.profile.id,
                    authenticatedClient: authenticatedClient,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    selectedKind: $transactionsSelectedKind,
                    isAddTransactionPresented: $isAddTransactionPresented,
                    isAddFixedExpensePresented: $isAddFixedExpensePresented,
                    isActive: selectedSection == .transactions,
                    reviewViewModel: reviewViewModel,
                    canEdit: viewModel.canEdit,
                    isArchivedPeriod: viewModel.isArchivedPeriod,
                    searchQuery: transactionsSearchQuery,
                    filter: transactionsFilter
                )
            } else {
                ProgressView()
            }
        }
    }

    private func reviewContent(viewModel: BudgetDetailViewModel) -> some View {
        TransactionReviewListView(
            viewModel: reviewViewModel,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            isActive: selectedSection == .review,
            canEdit: viewModel.canEdit
        )
    }

    /// Presented full width, not inside the 320pt drawer. Each gets a
    /// `NavigationStack` of its own so its pushes (People, Income, …) behave
    /// normally, and the shared ✕ so it closes the way every other sheet does.
    @ViewBuilder
    private func menuDestinationView(_ destination: BudgetMenuDestination) -> some View {
        if let authenticatedClient, let viewModel {
            NavigationStack {
                Group {
                    switch destination {
                    case .manage:
                        BudgetManageView(
                            viewModel: viewModel,
                            authenticatedClient: authenticatedClient,
                            currencyCode: currencyCode,
                            localeIdentifier: localeIdentifier,
                            onUpdated: onUpdated,
                            dismissParent: { onDeleted(); menuDestination = nil }
                        )
                    case .settings:
                        SettingsView(authenticatedClient: authenticatedClient, onUpdated: onUserUpdated)
                    case .help:
                        ChangelogView(
                            authenticatedClient: authenticatedClient,
                            localeIdentifier: localeIdentifier
                        )
                    case .allPeriods:
                        PeriodListView(
                            profile: viewModel.profile,
                            periods: viewModel.periods,
                            localeIdentifier: localeIdentifier,
                            onSelect: { id in
                                viewModel.selectPeriod(id: id)
                                menuDestination = nil
                            }
                        )
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton { menuDestination = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reportsContent: some View {
        if let authenticatedClient {
            ReportsPlaceholderView(authenticatedClient: authenticatedClient)
        } else {
            ProgressView()
        }
    }
}

#Preview {
    NavigationStack {
        BudgetDetailView(
            profile: .with {
                $0.id = "preview-budget"
                $0.name = "Household Budget"
                $0.cycle = .monthly
                $0.countryCode = "US"
            },
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            onUpdated: { _ in },
            onUserUpdated: { _ in },
            onDeleted: {}
        )
    }
    .environment(SessionStore())
}
