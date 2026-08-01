import SwiftUI
import WellSpentAPI

/// Adaptive navigation shell for a budget: a bottom tab bar on iPhone
/// (`.compact` horizontal size class), a `NavigationSplitView` sidebar on
/// iPad (`.regular`). Plan (allocations, 2C-1), Transactions (Variable +
/// Fixed, 2B-2/2B-3), and Manage (People/Income/Categories/Payment Methods,
/// 2A/2B-1) are all real. Expense Overview (actual vs. planned) lands in
/// 2C-2.
///
/// This view is pushed via `NavigationLink` onto `BudgetListView`'s
/// `NavigationStack`, but also nests its own per-tab `NavigationStack`s
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let authenticatedClient: ProtocolClient?
    private let currencyCode: String
    private let localeIdentifier: String
    private let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    private let onDeleted: () -> Void

    @State private var viewModel: BudgetDetailViewModel?
    @State private var selectedSection: BudgetSection = .manage
    @State private var notificationViewModel: NotificationBellViewModel?
    @State private var reviewViewModel: TransactionReviewViewModel?

    @State private var planSelectedKind: ExpensePlanView.PlanKind = .plan
    @State private var transactionsSelectedKind: TransactionsListView.TransactionKind = .variable
    @State private var isAddCategoryPresented = false
    @State private var isAddTransactionPresented = false
    @State private var isAddFixedExpensePresented = false
    @State private var isEditBudgetPresented = false
    @State private var isDeleteBudgetConfirmationPresented = false

    init(
        profile: Wellspent_V1_BudgetProfile,
        authenticatedClient: ProtocolClient?,
        currencyCode: String,
        localeIdentifier: String,
        onUpdated: @escaping (Wellspent_V1_BudgetProfile) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.authenticatedClient = authenticatedClient
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _viewModel = State(initialValue: authenticatedClient.map { BudgetDetailViewModel(profile: profile, authenticatedClient: $0) })
    }

    var body: some View {
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
        .navigationTitle(currentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            // Hoisted up from BudgetManageView so the Transactions tab has
            // `currentPeriod.id` (needed for `budget_period_id`) available
            // regardless of which tab is initially selected, not only once
            // the user happens to open Manage.
            await viewModel?.loadPeriod()
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
            // as `notificationViewModel`.
            guard let authenticatedClient, let viewModel else { return }
            if reviewViewModel == nil {
                reviewViewModel = TransactionReviewViewModel(
                    budgetProfileID: viewModel.profile.id,
                    authenticatedClient: authenticatedClient
                )
            }
            await reviewViewModel?.load()
        }
    }

    /// Combines notifying the parent list (so it drops the deleted profile
    /// from its own array) with actually popping this screen. Passed down as
    /// a single closure so `BudgetManageView` — which sits inside its own
    /// nested `NavigationStack` — doesn't need its own `@Environment(\.dismiss)`,
    /// which would only pop within that inner stack.
    private func dismissAfterDelete() {
        onDeleted()
        dismiss()
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
                manageContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.manage.title, systemImage: BudgetSection.manage.systemImage) }
            .tag(BudgetSection.manage)
        }
    }

    /// See the type-level doc comment — this tracks `selectedSection` to
    /// reproduce the per-tab title at the one level that's actually
    /// displayed.
    private var currentTitle: String {
        switch selectedSection {
        case .plan: "Expense Plan"
        case .transactions: "Transactions"
        case .review: "Review"
        case .manage: viewModel?.profile.name ?? ""
        }
    }

    /// Same reasoning as `currentTitle`, for the primary action button (+
    /// bell, common to every tab). Mirrors exactly what each leaf view used
    /// to declare in its own (non-rendering) `.toolbar`.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch selectedSection {
        case .plan:
            if planSelectedKind == .plan {
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
            if transactionsSelectedKind == .variable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddTransactionPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addTransactionButton")
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddFixedExpensePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addFixedExpenseButton")
                }
            }
        case .review:
            ToolbarItemGroup {}
        case .manage:
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Budget") { isEditBudgetPresented = true }
                    Button("Delete Budget", role: .destructive) { isDeleteBudgetConfirmationPresented = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("budgetDetailMenu")
            }
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
            case .manage:
                NavigationStack {
                    manageContent(viewModel: viewModel)
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
                isActive: selectedSection == .plan
            )
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func transactionsContent(viewModel: BudgetDetailViewModel) -> some View {
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
                isActive: selectedSection == .transactions
            )
        } else {
            ProgressView()
        }
    }

    private func reviewContent(viewModel: BudgetDetailViewModel) -> some View {
        TransactionReviewListView(
            viewModel: reviewViewModel,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            isActive: selectedSection == .review
        )
    }

    private func manageContent(viewModel: BudgetDetailViewModel) -> some View {
        BudgetManageView(
            viewModel: viewModel,
            authenticatedClient: authenticatedClient,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            onUpdated: onUpdated,
            isEditSheetPresented: $isEditBudgetPresented,
            isDeleteConfirmationPresented: $isDeleteBudgetConfirmationPresented,
            dismissParent: dismissAfterDelete
        )
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
            onDeleted: {}
        )
    }
}
