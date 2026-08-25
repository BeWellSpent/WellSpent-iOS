import Foundation
import SwiftUI
import WellSpentAPI

/// The app's home screen: the budget itself.
///
/// Until issue #60 this was a list of periods that pushed into the budget,
/// which meant every launch landed on a screen with exactly one meaningful
/// row on it — and an auto-push existed purely to skip past it. Now the
/// budget renders directly and the period list lives behind the ☰ menu
/// (`PeriodListView`). See docs/features/main-view-rework.md.
///
/// This view owns nothing about the budget itself; it resolves *which*
/// profile to show, handles the no-budget-yet case, and announces release
/// notes. Everything else is `BudgetDetailView`.
struct BudgetHomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel: BudgetHomeViewModel?

    /// One enum-driven sheet rather than several `.sheet(isPresented:)`
    /// modifiers. With more than one on a view SwiftUI can only reliably
    /// track a single presentation and the others get cross-wired — the
    /// documented cause of the Plaid double-tap bug (v1.25.0).
    private enum ActiveSheet: Identifiable {
        case createBudget
        case whatsNew

        var id: Int {
            switch self {
            case .createBudget: return 0
            case .whatsNew: return 1
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var changelogViewModel: ChangelogViewModel?
    /// Captured when the decision to announce is made, because the versions are
    /// marked seen in the same breath — reading them live afterwards would find
    /// nothing.
    @State private var announcedAppReleases: [Wellspent_V1_ChangelogRelease] = []
    @State private var announcedServerReleases: [Wellspent_V1_ChangelogRelease] = []

    var body: some View {
        NavigationStack {
            content
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .createBudget:
                        if let authenticatedClient = session.authenticatedClient {
                            BudgetSetupFlow(
                                authenticatedClient: authenticatedClient,
                                currencyCode: viewModel?.currencyCode ?? "USD",
                                localeIdentifier: viewModel?.localeIdentifier ?? "en"
                            ) { profile in
                                viewModel?.addCreatedProfile(profile)
                            }
                        }
                    case .whatsNew:
                        WhatsNewSheet(
                            appReleases: announcedAppReleases,
                            serverReleases: announcedServerReleases,
                            localeIdentifier: viewModel?.localeIdentifier ?? "en"
                        ) { activeSheet = nil }
                    }
                }
                .task {
                    guard viewModel == nil, let authenticatedClient = session.authenticatedClient else { return }
                    let model = BudgetHomeViewModel(authenticatedClient: authenticatedClient)
                    viewModel = model
                    await model.load()
                    await announceWhatsNewIfNeeded(authenticatedClient: authenticatedClient)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            if let profile = viewModel.profile {
                // `.id(profile.id)` so creating a budget after landing on the
                // empty state builds a fresh detail view rather than reusing
                // one whose view models were never given a profile.
                BudgetDetailView(
                    profile: profile,
                    authenticatedClient: session.authenticatedClient,
                    currencyCode: viewModel.currencyCode,
                    localeIdentifier: viewModel.localeIdentifier,
                    onUpdated: { viewModel.replaceProfile($0) },
                    onUserUpdated: { viewModel.replaceCurrentUser($0) },
                    onDeleted: { viewModel.removeProfile(id: profile.id) }
                )
                .id(profile.id)
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                emptyState(viewModel: viewModel)
            }
        } else {
            ProgressView()
        }
    }

    /// The one screen a brand-new account sees. It has no budget, so there is
    /// no Plan view to be home — this stands in until setup completes.
    private func emptyState(viewModel: BudgetHomeViewModel) -> some View {
        VStack(spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("No budgets yet")
                .font(.headline)
            Text("Create your first budget to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Create Budget") {
                activeSheet = .createBudget
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("addBudgetButton")

            Button("Log Out", role: .destructive) {
                session.endSession()
            }
            .accessibilityIdentifier("logoutButton")
            .padding(.top, 8)
        }
        .accessibilityIdentifier("emptyBudgetsState")
        .navigationTitle("Budgets")
    }

    /// Shows release notes the first time a version is opened.
    ///
    /// Marks the versions seen in the same breath as deciding, and reads the
    /// releases out first: a launch that announces nothing still has to be
    /// recorded, or the next launch would treat it as first-ever again and
    /// never announce anything.
    private func announceWhatsNewIfNeeded(authenticatedClient: ProtocolClient) async {
        guard changelogViewModel == nil else { return }
        let model = ChangelogViewModel(authenticatedClient: authenticatedClient)
        changelogViewModel = model
        await model.load()

        announcedAppReleases = model.unseenAppReleases
        announcedServerReleases = model.unseenServerReleases
        model.markCurrentVersionsSeen()

        // Never displace a sheet the user opened themselves.
        guard activeSheet == nil else { return }
        if !announcedAppReleases.isEmpty || !announcedServerReleases.isEmpty {
            activeSheet = .whatsNew
        }
    }
}

#Preview {
    BudgetHomeView()
        .environment(SessionStore())
}
