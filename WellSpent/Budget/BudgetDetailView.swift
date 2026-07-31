import SwiftUI
import WellSpentAPI

/// Adaptive navigation shell for a budget: a bottom tab bar on iPhone
/// (`.compact` horizontal size class), a `NavigationSplitView` sidebar on
/// iPad (`.regular`). Plan/Transactions are placeholders until Phase
/// 2B/2C; Manage already holds People/Income and gets Categories/Payment
/// Methods as they land in 2B.
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
        .navigationTitle(viewModel?.profile.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
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
            ComingSoonView(title: "Expense Plan", subtitle: "Coming in a future phase.")
                .tabItem { Label(BudgetSection.plan.title, systemImage: BudgetSection.plan.systemImage) }
                .tag(BudgetSection.plan)

            ComingSoonView(title: "Transactions", subtitle: "Coming in Phase 2B.")
                .tabItem { Label(BudgetSection.transactions.title, systemImage: BudgetSection.transactions.systemImage) }
                .tag(BudgetSection.transactions)

            NavigationStack {
                manageContent(viewModel: viewModel)
            }
            .tabItem { Label(BudgetSection.manage.title, systemImage: BudgetSection.manage.systemImage) }
            .tag(BudgetSection.manage)
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
                ComingSoonView(title: "Expense Plan", subtitle: "Coming in a future phase.")
            case .transactions:
                ComingSoonView(title: "Transactions", subtitle: "Coming in Phase 2B.")
            case .manage:
                NavigationStack {
                    manageContent(viewModel: viewModel)
                }
            }
        }
    }

    private func manageContent(viewModel: BudgetDetailViewModel) -> some View {
        BudgetManageView(
            viewModel: viewModel,
            authenticatedClient: authenticatedClient,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            onUpdated: onUpdated,
            dismissParent: dismissAfterDelete
        )
    }
}
