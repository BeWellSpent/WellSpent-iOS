import Foundation
import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Adaptive navigation shell for a budget: a bottom tab bar on iPhone
/// (`.compact` horizontal size class), a `NavigationSplitView` sidebar on
/// iPad (`.regular`). Four real destinations — Overview, Plan, Reports, More
/// — per docs/features/overview-plan-navigation-rework.md: Overview is the
/// home for *what actually happened* (the actual-breakdown chart, with
/// Transactions/Payments/Review as sub-tabs beneath it), Plan for *what you
/// intend to spend* (the per-category planned-amount editor). Overview and
/// Plan replaced the former Plan/Transactions/Review three-way split — see
/// that spec for the full before/after.
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
    /// Sub-destination within the Overview section — "what actually
    /// happened." Owned here, not a `Shared/` enum, same reason
    /// `transactionsSelectedKind` is: it drives which toolbar content shows
    /// at the one level that actually renders it (see the type-level doc
    /// comment above). `.overview` is the landing content itself (today's
    /// Expense Overview chart/actual-breakdown); `.transactions`/`.payments`/
    /// `.review` are the three sub-tabs beneath it.
    private enum OverviewSubTab: Hashable, CaseIterable {
        case overview
        case transactions
        case payments
        case review

        var title: String {
            let locale = AppLanguageStore.currentLocale
            switch self {
            case .overview: return String(localized: "Overview", bundle: AppLanguageStore.currentBundle, locale: locale)
            case .transactions: return String(localized: "Transactions", bundle: AppLanguageStore.currentBundle, locale: locale)
            case .payments: return String(localized: "Payments", bundle: AppLanguageStore.currentBundle, locale: locale)
            case .review: return String(localized: "Review", bundle: AppLanguageStore.currentBundle, locale: locale)
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SessionStore.self) private var session
    private let authenticatedRESTClient: WellSpentREST.Client?
    private let currencyCode: String
    private let localeIdentifier: String
    private let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    private let onUserUpdated: (Wellspent_V1_User) -> Void
    private let onDeleted: () -> Void

    @State private var viewModel: BudgetDetailViewModel?
    @State private var selectedSection: BudgetSection = .overview
    @State private var notificationViewModel: NotificationBellViewModel?
    @State private var reviewViewModel: TransactionReviewViewModel?

    @State private var overviewSelectedSubTab: OverviewSubTab = .overview
    @State private var transactionsSelectedKind: TransactionsListView.TransactionKind = .variable
    @State private var transactionsSearchQuery = ""
    /// Search starts hidden (issue #92 follow-up) — revealed by the toolbar's
    /// search icon (see `toolbarContent`'s `.overview` case) rather than
    /// always shown above the list. Only relevant to the Transactions/
    /// Payments sub-tabs.
    @State private var isTransactionsSearchVisible = false
    @State private var isAddCategoryPresented = false
    @State private var isAddTransactionPresented = false
    @State private var isAddFixedExpensePresented = false
    @State private var isMenuPresented = false
    /// Bumped whenever the Focused View toggle changes in `BudgetMenuSheet`,
    /// so Plan/Overview rebuild and refetch immediately instead of
    /// showing the old scope until the user leaves and re-enters the tab.
    /// Folded into `.id(period.id)` below — the same trick that already
    /// forces a fresh subtree (and thus a fresh `.task`/load) on a period
    /// switch, reused here for the same reason.
    @State private var focusedViewToken = UUID()
    @State private var isPaymentMethodRequiredPresented = false
    @State private var isPaymentMethodsPresented = false

    init(
        profile: Wellspent_V1_BudgetProfile,
        periodID: String? = nil,
        authenticatedRESTClient: WellSpentREST.Client?,
        currencyCode: String,
        localeIdentifier: String,
        onUpdated: @escaping (Wellspent_V1_BudgetProfile) -> Void,
        onUserUpdated: @escaping (Wellspent_V1_User) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.authenticatedRESTClient = authenticatedRESTClient
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.onUpdated = onUpdated
        self.onUserUpdated = onUserUpdated
        self.onDeleted = onDeleted
        _viewModel = State(initialValue: authenticatedRESTClient.map {
            BudgetDetailViewModel(profile: profile, overridePeriodID: periodID, restClient: $0)
        })
    }

    var body: some View {
        content
            .navigationTitle(selectedSection.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
    }

    /// Intercepts `more`, which is a button wearing a tab's clothes: it opens
    /// the menu sheet and must never become the selection. The getter always
    /// reports the real section, so SwiftUI re-reads and leaves the previous
    /// tab highlighted with no visible flicker.
    private var tabSelection: Binding<BudgetSection> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                if newValue == .more {
                    isMenuPresented = true
                } else {
                    selectedSection = newValue
                }
            }
        )
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
        .task {
            // Hoisted up from BudgetManageView so the Overview section has
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
        .sheet(isPresented: $isMenuPresented) {
            if let viewModel {
                BudgetMenuSheet(
                    viewModel: viewModel,
                    authenticatedRESTClient: authenticatedRESTClient,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    onUpdated: onUpdated,
                    onUserUpdated: onUserUpdated,
                    onDeleted: onDeleted,
                    onFocusedViewChanged: { focusedViewToken = UUID() }
                )
            }
        }
        .alert("Add a payment method first", isPresented: $isPaymentMethodRequiredPresented) {
            Button("Add a payment method") { isPaymentMethodsPresented = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Transactions need a payment method — cash, a card, or a bank account — so you can see where the money went. Add one and you'll be able to record transactions right away.")
        }
        .sheet(isPresented: $isPaymentMethodsPresented) {
            // Presented here rather than switching to the Manage tab and
            // pushing: dismissing lands the user back on Overview, ready to
            // add the thing they came for.
            if let authenticatedRESTClient, let viewModel {
                NavigationStack {
                    PaymentMethodsListView(
                        budgetProfileID: viewModel.profile.id,
                        authenticatedRESTClient: authenticatedRESTClient,
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
            // Created once and subscribed for the lifetime of this screen
            // (not per-toolbar-appearance) — every tab's bell shares this
            // same instance, so switching tabs never restarts the
            // subscription. Refreshes on push, not a timer — no polling.
            guard let authenticatedRESTClient, let viewModel else { return }
            if notificationViewModel == nil {
                notificationViewModel = NotificationBellViewModel(
                    budgetProfileID: viewModel.profile.id,
                    restClient: authenticatedRESTClient
                )
            }
            await notificationViewModel?.observePushEvents()
        }
        .task {
            // Created once here (not inside `TransactionReviewListView`) so
            // the pending count backs the Overview tab's badge — same
            // reasoning as `notificationViewModel`. Subscribed (not polled)
            // so the badge — visible from every tab — updates on a matching
            // push without the user having to enter the Review sub-tab first.
            guard let authenticatedRESTClient, let viewModel else { return }
            if reviewViewModel == nil {
                reviewViewModel = TransactionReviewViewModel(
                    budgetProfileID: viewModel.profile.id,
                    currentUserID: session.userID,
                    restClient: authenticatedRESTClient
                )
            }
            await reviewViewModel?.observePushEvents()
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
        TabView(selection: tabSelection) {
            NavigationStack {
                overviewContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.overview.title, systemImage: BudgetSection.overview.systemImage) }
            .tag(BudgetSection.overview)
            .badge(reviewViewModel?.pendingReviews.count ?? 0)

            NavigationStack {
                planContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.plan.title, systemImage: BudgetSection.plan.systemImage) }
            .tag(BudgetSection.plan)

            NavigationStack {
                reportsContent
            }
            .tabItem { Label(BudgetSection.reports.title, systemImage: BudgetSection.reports.systemImage) }
            .tag(BudgetSection.reports)

            // Content is never shown: selecting this tag opens the menu sheet
            // and the selection snaps back. It still needs *a* view, or the
            // tab item has nothing to hang off.
            Color.clear
                .tabItem { Label(BudgetSection.more.title, systemImage: BudgetSection.more.systemImage) }
                .tag(BudgetSection.more)
        }
    }

    /// Tracks `selectedSection` (and, for Overview, `overviewSelectedSubTab`)
    /// to reproduce each tab's primary action (plus the bell, common to
    /// every tab) at the one level that actually renders — see the
    /// type-level doc comment. The menu is not here: it opens from the
    /// bottom bar's "More" item.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch selectedSection {
        case .overview:
            if overviewSelectedSubTab != .review, let viewModel {
                ToolbarItem(placement: .principal) {
                    TransactionsPeriodControl(
                        currentPeriod: viewModel.currentPeriod,
                        periods: viewModel.periods,
                        profile: viewModel.profile,
                        localeIdentifier: localeIdentifier,
                        onSelect: { viewModel.selectPeriod(id: $0) }
                    )
                }
            }
            if overviewSelectedSubTab == .transactions || overviewSelectedSubTab == .payments {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isTransactionsSearchVisible.toggle()
                        if !isTransactionsSearchVisible { transactionsSearchQuery = "" }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityIdentifier("transactionsSearchToggleButton")
                }
                if viewModel?.canEdit == true && viewModel?.isArchivedPeriod != true {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            startAddingTransactionForCurrentTab()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("addTransactionButton")
                    }
                }
            }
        case .plan:
            // No more Plan/Overview toggle to check here — Overview's own
            // content moved to its own BudgetSection, so Plan is always just
            // the category planned-amount editor now.
            if viewModel?.canEdit == true {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddCategoryPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addPlanCategoryButton")
                }
            }
        case .reports, .more:
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
            set: {
                guard let newValue = $0 else { return }
                if newValue == .more {
                    isMenuPresented = true
                } else {
                    selectedSection = newValue
                }
            }
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
            case .overview:
                NavigationStack {
                    overviewContent(viewModel: viewModel)
                }
            case .plan:
                NavigationStack {
                    planContent(viewModel: viewModel)
                }
            case .reports:
                NavigationStack {
                    reportsContent
                }
            case .more:
                // Unreachable: `more` never becomes the selection.
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func planContent(viewModel: BudgetDetailViewModel) -> some View {
        if let authenticatedRESTClient, let period = viewModel.currentPeriod, !period.id.isEmpty {
            ExpensePlanView(
                budgetPeriodID: period.id,
                budgetProfileID: viewModel.profile.id,
                authenticatedRESTClient: authenticatedRESTClient,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                isAddCategoryPresented: $isAddCategoryPresented,
                isActive: selectedSection == .plan,
                canEdit: viewModel.canEdit
            )
            // Switching period must rebuild this subtree, not just re-pass the
            // id. ExpensePlanView creates its view model once (`if viewModel ==
            // nil`) and captures budgetPeriodID at that moment, so a plain
            // parameter change left it reloading the period the user had
            // navigated away from. The parent owns the sheet flags as @State,
            // so those survive; only the period-scoped internals are
            // discarded, which is exactly what should happen.
            // `focusedViewToken` rides along for the same reason: flipping
            // Focused View needs the same fresh reload a period switch gets.
            .id("\(period.id)|\(focusedViewToken)")
        } else {
            ProgressView()
        }
    }

    /// Overview's own container: the chart/actual-breakdown landing content
    /// plus a sub-tab picker switching to Transactions/Payments/Review.
    @ViewBuilder
    private func overviewContent(viewModel: BudgetDetailViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("View", selection: $overviewSelectedSubTab) {
                Text(OverviewSubTab.overview.title).tag(OverviewSubTab.overview)
                Text(OverviewSubTab.transactions.title).tag(OverviewSubTab.transactions)
                Text(OverviewSubTab.payments.title).tag(OverviewSubTab.payments)
                Text(reviewSubTabLabel).tag(OverviewSubTab.review)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .accessibilityIdentifier("overviewSubTabPicker")

            if isTransactionsSearchVisible && (overviewSelectedSubTab == .transactions || overviewSelectedSubTab == .payments) {
                transactionsSearchField
            }

            switch overviewSelectedSubTab {
            case .overview:
                overviewLandingContent(viewModel: viewModel)
            case .transactions:
                transactionsSubTabContent(viewModel: viewModel)
            case .payments:
                paymentsSubTabContent(viewModel: viewModel)
            case .review:
                reviewContent(viewModel: viewModel)
            }
        }
    }

    /// In-content indicator for the Review sub-tab, since it no longer has
    /// its own `.tabItem` `.badge(_:)` to carry one (that moved to the
    /// Overview tab item itself — see `tabView`). Plain count suffix rather
    /// than a true `.badge(_:)` modifier: a segmented `Picker`'s individual
    /// segments don't support that modifier.
    private var reviewSubTabLabel: String {
        let count = reviewViewModel?.pendingReviews.count ?? 0
        return count > 0 ? "\(OverviewSubTab.review.title) (\(count))" : OverviewSubTab.review.title
    }

    @ViewBuilder
    private func overviewLandingContent(viewModel: BudgetDetailViewModel) -> some View {
        if let authenticatedRESTClient, let period = viewModel.currentPeriod, !period.id.isEmpty {
            ExpenseOverviewListView(
                budgetPeriodID: period.id,
                budgetProfileID: viewModel.profile.id,
                authenticatedRESTClient: authenticatedRESTClient,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            )
            // Same reason as planContent's — see there.
            .id("\(period.id)|\(focusedViewToken)")
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func transactionsSubTabContent(viewModel: BudgetDetailViewModel) -> some View {
        if let authenticatedRESTClient, let period = viewModel.currentPeriod, !period.id.isEmpty {
            TransactionsListView(
                budgetPeriodID: period.id,
                budgetProfileID: viewModel.profile.id,
                authenticatedRESTClient: authenticatedRESTClient,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                selectedKind: $transactionsSelectedKind,
                isAddTransactionPresented: $isAddTransactionPresented,
                isAddFixedExpensePresented: $isAddFixedExpensePresented,
                isActive: selectedSection == .overview && overviewSelectedSubTab == .transactions,
                reviewViewModel: reviewViewModel,
                canEdit: viewModel.canEdit,
                isArchivedPeriod: viewModel.isArchivedPeriod,
                searchQuery: transactionsSearchQuery
            )
            // Same reason as planContent's — see there.
            .id("\(period.id)|\(focusedViewToken)")
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func paymentsSubTabContent(viewModel: BudgetDetailViewModel) -> some View {
        if let authenticatedRESTClient, let period = viewModel.currentPeriod, !period.id.isEmpty {
            PaymentsListView(
                budgetPeriodID: period.id,
                budgetProfileID: viewModel.profile.id,
                authenticatedRESTClient: authenticatedRESTClient,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                isAddTransactionPresented: $isAddTransactionPresented,
                isActive: selectedSection == .overview && overviewSelectedSubTab == .payments,
                reviewViewModel: reviewViewModel,
                canEdit: viewModel.canEdit,
                isArchivedPeriod: viewModel.isArchivedPeriod,
                searchQuery: transactionsSearchQuery
            )
            // Same reason as planContent's — see there.
            .id("\(period.id)|\(focusedViewToken)")
        } else {
            ProgressView()
        }
    }

    /// Same plain `TextField` this screen has always used for search — see
    /// the history in docs/features (v1.27.1): SwiftUI's native `.searchable`
    /// never installs a search bar at all on this doubly-nested
    /// NavigationStack architecture. Gated behind the toolbar's search icon
    /// (see `toolbarContent`'s `.overview` case) and shown above whichever of
    /// the Transactions/Payments sub-tabs is active.
    private var transactionsSearchField: some View {
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
    }

    /// One shared add entry point for the Transactions/Payments sub-tabs
    /// (issue #92 follow-up) — dispatches to whichever sheet the current
    /// sub-tab needs; the payment-method-required gate is unchanged. A no-op
    /// on the Overview landing content or the Review sub-tab, where the "+"
    /// isn't shown in the first place (see `toolbarContent`).
    private func startAddingTransactionForCurrentTab() {
        switch overviewSelectedSubTab {
        case .payments:
            startAddingTransaction { isAddTransactionPresented = true }
        case .transactions:
            switch transactionsSelectedKind {
            case .fixed:
                startAddingTransaction { isAddFixedExpensePresented = true }
            case .variable:
                startAddingTransaction { isAddTransactionPresented = true }
            }
        case .overview, .review:
            break
        }
    }

    private func reviewContent(viewModel: BudgetDetailViewModel) -> some View {
        TransactionReviewListView(
            viewModel: reviewViewModel,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            isActive: selectedSection == .overview && overviewSelectedSubTab == .review,
            canEdit: viewModel.canEdit
        )
    }

    @ViewBuilder
    private var reportsContent: some View {
        if let authenticatedRESTClient {
            ReportsPlaceholderView(authenticatedRESTClient: authenticatedRESTClient)
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
            authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            onUpdated: { _ in },
            onUserUpdated: { _ in },
            onDeleted: {}
        )
    }
    .environment(SessionStore())
}
