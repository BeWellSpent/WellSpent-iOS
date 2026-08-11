import Foundation
import SwiftUI
import WellSpentAPI

struct BudgetListView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel: BudgetListViewModel?
    @State private var isCreateSheetPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var selectedYear: Int?
    /// Drives a one-shot auto-push straight into the active period's
    /// `BudgetDetailView` on launch — there's no point landing on a list
    /// with exactly one entry. Only fires once per view lifetime
    /// (`hasAttemptedAutoNavigate` guards it): without that guard, popping
    /// back from the auto-navigated detail view would just immediately
    /// re-push the same destination, making "back" from it useless. Scoped
    /// to the single-profile case only — a user can own one budget *and* be
    /// a member of unlimited shared ones, and there's no "primary"/"last
    /// viewed" concept in the data model to disambiguate which of several
    /// to jump into, so multi-profile users still see the list as before.
    @State private var isAutoNavigatingToActiveBudget = false
    @State private var hasAttemptedAutoNavigate = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Budgets")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            if let authenticatedClient = session.authenticatedClient {
                                SettingsView(authenticatedClient: authenticatedClient) { updated in
                                    viewModel?.replaceCurrentUser(updated)
                                }
                            }
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier("settingsButton")
                    }
                    // Only one owned budget profile is allowed per account —
                    // see docs/features/budget-list-view-rework.md — so "Add"
                    // only shows once the user has none.
                    if viewModel?.profiles.isEmpty != false {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                isCreateSheetPresented = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityIdentifier("addBudgetButton")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Log Out", role: .destructive) {
                            session.endSession()
                        }
                        .accessibilityIdentifier("logoutButton")
                    }
                }
                .alert("Delete Budget", isPresented: $isDeleteConfirmationPresented) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        if let profile = viewModel?.profile {
                            Task { await viewModel?.delete(profile) }
                        }
                    }
                } message: {
                    Text("This will permanently delete \(viewModel?.profile?.name ?? "this budget") and everything in it. This cannot be undone.")
                }
                .sheet(isPresented: $isCreateSheetPresented) {
                    if let authenticatedClient = session.authenticatedClient {
                        BudgetSetupFlow(
                            authenticatedClient: authenticatedClient,
                            currencyCode: viewModel?.currencyCode ?? "USD",
                            localeIdentifier: viewModel?.localeIdentifier ?? "en"
                        ) { profile in
                            viewModel?.addCreatedProfile(profile)
                        }
                    }
                }
                .task {
                    guard viewModel == nil, let authenticatedClient = session.authenticatedClient else { return }
                    let model = BudgetListViewModel(authenticatedClient: authenticatedClient)
                    viewModel = model
                    await model.load()
                    attemptAutoNavigateIfNeeded()
                }
                .refreshable {
                    await viewModel?.load()
                }
                .navigationDestination(isPresented: $isAutoNavigatingToActiveBudget) {
                    if let viewModel, let profile = viewModel.profile {
                        BudgetDetailView(
                            profile: profile,
                            authenticatedClient: session.authenticatedClient,
                            currencyCode: viewModel.currencyCode,
                            localeIdentifier: viewModel.localeIdentifier,
                            onUpdated: { updated in viewModel.replaceProfile(updated) },
                            onDeleted: { viewModel.removeProfile(id: profile.id) }
                        )
                    }
                }
        }
    }

    /// Only auto-navigates when there's exactly one budget (unambiguous)
    /// and it actually has a period to show — a brand-new profile with zero
    /// periods would land on an empty detail view with no way back to
    /// create one, so staying on the list (which already has its own
    /// "No periods yet" state) is safer in that edge case.
    private func attemptAutoNavigateIfNeeded() {
        guard !hasAttemptedAutoNavigate else { return }
        hasAttemptedAutoNavigate = true
        guard let viewModel, PeriodGrouping.shouldAutoNavigateToSingleActiveBudget(profileCount: viewModel.profiles.count, hasPeriods: !viewModel.yearGroups.isEmpty) else { return }
        isAutoNavigatingToActiveBudget = true
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            VStack(spacing: 0) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.profiles.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    budgetList(viewModel: viewModel)
                }

                versionFooter
            }
        } else {
            ProgressView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No budgets yet")
                .font(.headline)
            Text("Tap + to create your first budget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("emptyBudgetsState")
    }

    private var years: [Int] { viewModel?.yearGroups.map(\.year) ?? [] }

    private var effectiveYear: Int? {
        if let selectedYear, years.contains(selectedYear) { return selectedYear }
        return years.first
    }

    private func periodsForYear(_ viewModel: BudgetListViewModel) -> [Wellspent_V1_BudgetPeriod] {
        viewModel.yearGroups.first { $0.year == effectiveYear }?.periods ?? []
    }

    /// Shows the (at most one) owned profile's periods, grouped by year with
    /// a year picker — replaces the old profile-card list now that a user
    /// only ever has one budget. See docs/features/budget-list-view-rework.md.
    private func budgetList(viewModel: BudgetListViewModel) -> some View {
        List {
            if let profile = viewModel.profile {
                Section {
                    HStack {
                        Text(profile.name)
                            .font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityIdentifier("deleteBudgetButton")
                    }
                }

                if years.isEmpty {
                    Section {
                        Text("No periods yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("Year", selection: Binding(
                            get: { effectiveYear ?? years[0] },
                            set: { selectedYear = $0 }
                        )) {
                            ForEach(years, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .accessibilityIdentifier("yearPicker")
                    }

                    Section {
                        ForEach(periodsForYear(viewModel), id: \.id) { period in
                            NavigationLink {
                                BudgetDetailView(
                                    profile: profile,
                                    periodID: period.id,
                                    authenticatedClient: session.authenticatedClient,
                                    currencyCode: viewModel.currencyCode,
                                    localeIdentifier: viewModel.localeIdentifier,
                                    onUpdated: { updated in viewModel.replaceProfile(updated) },
                                    onDeleted: { viewModel.removeProfile(id: profile.id) }
                                )
                            } label: {
                                periodRow(period, localeIdentifier: viewModel.localeIdentifier)
                            }
                            .accessibilityIdentifier("periodRow_\(PeriodGrouping.label(for: period, localeIdentifier: viewModel.localeIdentifier))")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func periodRow(_ period: Wellspent_V1_BudgetPeriod, localeIdentifier: String) -> some View {
        HStack {
            Text(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))
            Spacer()
            (period.isArchived ? Text("Archived") : Text("Active"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(period.isArchived ? Color.gray.opacity(0.2) : Color.green.opacity(0.2))
                .foregroundStyle(period.isArchived ? Color.secondary : Color.green)
                .clipShape(Capsule())
        }
    }

    private var versionFooter: some View {
        Group {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
        }
    }
}

#Preview {
    BudgetListView()
        .environment(SessionStore())
}
