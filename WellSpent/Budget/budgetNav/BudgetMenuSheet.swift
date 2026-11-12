import Foundation
import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Everything that isn't a frequent destination, opened from the bottom bar's
/// "More": this budget (and Just me), its panels, alerts and preferences,
/// your account, help, and logging out. Every option sits on this one sheet;
/// the separate "Manage budget" page it used to push is gone.
///
/// A sheet from the bottom bar rather than a left drawer: it rises from where
/// it was tapped. See docs/features/main-view-rework.md.
struct BudgetMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    let viewModel: BudgetDetailViewModel
    let authenticatedRESTClient: WellSpentREST.Client?
    let currentUser: Wellspent_V1_User?
    let currencyCode: String
    let localeIdentifier: String
    let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    let onUserUpdated: (Wellspent_V1_User) -> Void
    let onDeleted: () -> Void
    /// Fired when Just me flips, so the tabs behind this sheet refetch under the new scope.
    let onFocusedViewChanged: () -> Void

    /// Reused for the Just me switch: it already resolves the caller's person and saves the preference.
    @State private var preferencesViewModel: PreferencesViewModel?
    @State private var isEditSheetPresented = false
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    budgetCard
                    if let authenticatedRESTClient {
                        HomeSectionHeader(title: Text("Budget"))
                        budgetRows(authenticatedRESTClient)
                        HomeSectionHeader(title: Text("Notifications and preferences"))
                        preferenceRows(authenticatedRESTClient)
                        HomeSectionHeader(title: Text("Account"))
                        accountRows(authenticatedRESTClient)
                    }
                    logoutButton
                    versionFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard let authenticatedRESTClient else { return }
                if preferencesViewModel == nil {
                    preferencesViewModel = PreferencesViewModel(
                        budgetProfileID: viewModel.profile.id,
                        currentUserID: session.userID,
                        restClient: authenticatedRESTClient
                    )
                }
                await preferencesViewModel?.load()
            }
            .sheet(isPresented: $isEditSheetPresented) {
                if let authenticatedRESTClient {
                    EditBudgetSheet(profile: viewModel.profile, restClient: authenticatedRESTClient) { updated in
                        viewModel.applyUpdatedProfile(updated)
                        onUpdated(updated)
                    }
                }
            }
            .confirmationDialog("Delete this budget?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await viewModel.delete() {
                            onDeleted()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: Header and budget card

    private var header: some View {
        HStack {
            Text("More")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("sheetCancelButton")
        }
        .padding(.leading, 4)
        .padding(.top, 12)
    }

    private var roleText: Text {
        viewModel.canManageUsers ? Text("Admin") : viewModel.canEdit ? Text("Collaborator") : Text("Viewer")
    }

    private var budgetCard: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(verbatim: String(viewModel.profile.name.prefix(1)).uppercased())
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(verbatim: viewModel.profile.name)
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                            roleText
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        Text(verbatim: budgetSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    if viewModel.canManageUsers {
                        Menu {
                            Button("Edit Budget") { isEditSheetPresented = true }
                            Button("Delete Budget", role: .destructive) { isDeleteConfirmationPresented = true }
                        } label: {
                            Text("Edit")
                                .fontWeight(.semibold)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("budgetDetailMenu")
                    }
                }

                justMeToggle

                if let errorMessage = viewModel.errorMessage {
                    InlineErrorBanner(message: errorMessage)
                }
            }
        }
    }

    private var budgetSubtitle: String {
        let cycle = BudgetCycleLabel.text(for: viewModel.profile.cycle)
        guard let period = viewModel.currentPeriod else { return cycle }
        return "\(cycle) · \(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))"
    }

    /// One tap from the root: flipped far more often than a set-once preference.
    @ViewBuilder
    private var justMeToggle: some View {
        if let preferencesViewModel, preferencesViewModel.isLinkedMember {
            Divider()
            Toggle(isOn: Binding(
                get: { preferencesViewModel.focusedView },
                set: { newValue in
                    Task {
                        await preferencesViewModel.updateFocusedView(newValue)
                        // Fires on success or rollback: `focusedView` now holds the value the tabs should reflect.
                        onFocusedViewChanged()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just me").fontWeight(.semibold)
                    Text("Only your own numbers, plus anything not assigned to anyone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)
            .disabled(preferencesViewModel.isSaving)
            .accessibilityIdentifier("focusedViewPreference")
        }
    }

    // MARK: Rows

    private func budgetRows(_ client: WellSpentREST.Client) -> some View {
        MoreRowGroup {
            NavigationLink {
                PeopleListView(
                    budgetProfileID: viewModel.profile.id,
                    budgetOwnerUserID: viewModel.profile.userID,
                    authenticatedRESTClient: client,
                    canManageUsers: viewModel.canManageUsers
                )
            } label: {
                MoreRow(title: Text("People"), systemImage: "person.2", tint: .purple)
            }
            .accessibilityIdentifier("peopleNavLink")

            MoreRowDivider()
            NavigationLink {
                IncomeListView(
                    budgetProfileID: viewModel.profile.id,
                    budgetCountryCode: viewModel.profile.countryCode,
                    authenticatedRESTClient: client,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    canEdit: viewModel.canEdit
                )
            } label: {
                MoreRow(title: Text("Income"), systemImage: "arrow.up", tint: .green)
            }
            .accessibilityIdentifier("incomeNavLink")

            MoreRowDivider()
            NavigationLink {
                SavingsListView(
                    budgetProfileID: viewModel.profile.id,
                    periodStartDate: viewModel.currentPeriod?.startDate.dateOnly,
                    authenticatedRESTClient: client,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    canEdit: viewModel.canEdit
                )
            } label: {
                MoreRow(title: Text("Savings"), systemImage: "lock", tint: .green)
            }
            .accessibilityIdentifier("savingsNavLink")

            MoreRowDivider()
            NavigationLink {
                CategoriesListView(
                    budgetProfileID: viewModel.profile.id,
                    authenticatedRESTClient: client,
                    canEdit: viewModel.canEdit
                )
            } label: {
                MoreRow(title: Text("Categories"), systemImage: "square.grid.2x2", tint: .orange)
            }
            .accessibilityIdentifier("categoriesNavLink")

            MoreRowDivider()
            NavigationLink {
                PaymentMethodsListView(
                    budgetProfileID: viewModel.profile.id,
                    authenticatedRESTClient: client,
                    canEdit: viewModel.canEdit
                )
            } label: {
                MoreRow(title: Text("Payment Methods"), systemImage: "creditcard", tint: .blue)
            }
            .accessibilityIdentifier("paymentMethodsNavLink")

            if viewModel.canManageUsers {
                MoreRowDivider()
                NavigationLink {
                    InvitesListView(
                        budgetProfileID: viewModel.profile.id,
                        budgetOwnerUserID: viewModel.profile.userID,
                        authenticatedRESTClient: client
                    )
                } label: {
                    MoreRow(title: Text("Invitations"), systemImage: "envelope", tint: .blue)
                }
                .accessibilityIdentifier("invitationsNavLink")
            }

            if viewModel.profile.countryCode == "US" {
                MoreRowDivider()
                NavigationLink {
                    PlaidConnectionsPanelView(authenticatedRESTClient: client, budgetProfileID: viewModel.profile.id)
                } label: {
                    MoreRow(title: Text("Bank Connections"), systemImage: "building.columns", tint: .gray)
                }
                .accessibilityIdentifier("bankConnectionsNavLink")
            }
        }
    }

    private func preferenceRows(_ client: WellSpentREST.Client) -> some View {
        MoreRowGroup {
            NavigationLink {
                AlertsListView(budgetProfileID: viewModel.profile.id, authenticatedRESTClient: client)
            } label: {
                MoreRow(title: Text("Alerts"), subtitle: Text("What notifies you, in the app or by email"), systemImage: "bell", tint: .red)
            }
            .accessibilityIdentifier("alertSettingsNavLink")

            MoreRowDivider()
            NavigationLink {
                PreferencesView(budgetProfileID: viewModel.profile.id, authenticatedRESTClient: client)
            } label: {
                MoreRow(
                    title: Text("Preferences"),
                    subtitle: viewModel.canManageUsers ? Text("Charts, matching, carryover, plan follows paid") : Text("Charts, matching"),
                    systemImage: "slider.horizontal.3",
                    tint: .gray
                )
            }
            .accessibilityIdentifier("preferencesNavLink")
        }
    }

    private func accountRows(_ client: WellSpentREST.Client) -> some View {
        MoreRowGroup {
            NavigationLink {
                SettingsView(
                    publicRESTClient: session.publicRESTClient,
                    restClient: client,
                    csharpAuthenticatedRESTClient: client,
                    onUpdated: onUserUpdated
                )
            } label: {
                AccountRow(user: currentUser)
            }
            .accessibilityIdentifier("settingsButton")

            MoreRowDivider()
            NavigationLink {
                ChangelogView(authenticatedClient: client, localeIdentifier: localeIdentifier)
            } label: {
                MoreRow(title: Text("Help and what's new"), systemImage: "questionmark.circle", tint: .gray)
            }
            .accessibilityIdentifier("helpLink")
        }
    }

    // MARK: Footer

    private var logoutButton: some View {
        Button(role: .destructive) {
            session.endSession()
        } label: {
            Text("Log Out")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .padding(.top, 8)
        .accessibilityIdentifier("logoutButton")
    }

    @ViewBuilder
    private var versionFooter: some View {
        if let version = AppVersion.displayText {
            Text(verbatim: version)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    let restClient = RESTClient.makePublicClient(baseURL: "http://localhost:1")
    return BudgetMenuSheet(
        viewModel: BudgetDetailViewModel(
            profile: .with {
                $0.id = "preview-budget"
                $0.name = "Household Budget"
                $0.cycle = .monthly
                $0.countryCode = "US"
            },
            restClient: restClient
        ),
        authenticatedRESTClient: restClient,
        currentUser: .with {
            $0.firstName = "Jane"
            $0.lastName = "Doe"
            $0.email = "jane@example.com"
            $0.plan = .free
        },
        currencyCode: "USD",
        localeIdentifier: "en",
        onUpdated: { _ in },
        onUserUpdated: { _ in },
        onDeleted: {},
        onFocusedViewChanged: {}
    )
    .environment(SessionStore())
}
