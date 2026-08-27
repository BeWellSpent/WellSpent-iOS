import Foundation
import SwiftUI
import WellSpentAPI

/// Everything that isn't a frequent destination: which period you're looking
/// at, the manage panels, settings, help, and logging out.
///
/// Presented as a sheet from the **"More" item in the bottom bar**, not from
/// a hamburger in the navigation bar. A sheet rises from the bottom of the
/// screen, so triggering it from the bottom bar is where it visibly comes
/// from; a leading toolbar button implied a panel sliding in from the left,
/// which is a promise a sheet doesn't keep.
///
/// A real left-edge drawer was built and rejected — it is in the history of
/// this file if it is ever wanted back. Web keeps its own `Drawer`, and the
/// two clients deliberately differ here: what has to match is the *contents
/// and their order*, not the animation. See docs/features/main-view-rework.md.
///
/// The period switcher lists only the current period's own year. A budget
/// accumulates twelve periods a year forever, so the full history belongs on
/// its own screen (`PeriodListView`) rather than in a menu that would grow
/// without bound.
struct BudgetMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    let viewModel: BudgetDetailViewModel
    let authenticatedClient: ProtocolClient?
    let currencyCode: String
    let localeIdentifier: String
    let onUpdated: (Wellspent_V1_BudgetProfile) -> Void
    let onUserUpdated: (Wellspent_V1_User) -> Void
    let onDeleted: () -> Void

    /// Periods sharing a year with whatever is currently being shown —
    /// including archived ones, since switching to a past period is exactly
    /// what this control is for.
    private var periodsThisYear: [Wellspent_V1_BudgetPeriod] {
        guard let current = viewModel.currentPeriod else { return [] }
        let year = Calendar.current.component(.year, from: current.startDate.dateOnly)
        return viewModel.periods.filter {
            Calendar.current.component(.year, from: $0.startDate.dateOnly) == year
        }
    }

    var body: some View {
        NavigationStack {
            List {
                periodSection
                destinationsSection
                logoutSection
                versionSection
            }
            .navigationTitle(viewModel.profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var periodSection: some View {
        Section("Period") {
            ForEach(periodsThisYear, id: \.id) { period in
                Button {
                    viewModel.selectPeriod(id: period.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))
                            .foregroundStyle(.primary)
                        Spacer()
                        if period.id == viewModel.currentPeriod?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        } else if period.isArchived {
                            Text("Archived")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("menuPeriodRow_\(PeriodGrouping.label(for: period, localeIdentifier: localeIdentifier))")
            }

            NavigationLink {
                PeriodListView(
                    profile: viewModel.profile,
                    periods: viewModel.periods,
                    localeIdentifier: localeIdentifier,
                    onSelect: { id in
                        viewModel.selectPeriod(id: id)
                        dismiss()
                    }
                )
            } label: {
                Label("View all periods", systemImage: "calendar")
            }
            .accessibilityIdentifier("viewAllPeriodsLink")
        }
    }

    @ViewBuilder
    private var destinationsSection: some View {
        Section {
            if let authenticatedClient {
                NavigationLink {
                    BudgetManageView(
                        viewModel: viewModel,
                        authenticatedClient: authenticatedClient,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier,
                        onUpdated: onUpdated,
                        // Deleting the budget removes the thing this whole
                        // sheet describes, so close the sheet too — the home
                        // view underneath falls back to its empty state.
                        dismissParent: { onDeleted(); dismiss() }
                    )
                } label: {
                    Label("Manage budget", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("manageBudgetLink")

                NavigationLink {
                    SettingsView(
                        authenticatedClient: authenticatedClient,
                        publicRESTClient: session.publicRESTClient,
                        restClient: session.authenticatedRESTClient ?? session.publicRESTClient,
                        onUpdated: onUserUpdated
                    )
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settingsButton")

                // A shortcut to what Settings' own Help section holds, not a
                // second copy of it — issue #60 asks for Help to be reachable
                // from this menu directly.
                NavigationLink {
                    ChangelogView(
                        authenticatedClient: session.authenticatedRESTClient ?? session.publicRESTClient,
                        localeIdentifier: localeIdentifier
                    )
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("helpLink")
            }
        }
    }

    private var logoutSection: some View {
        Section {
            // Keeps its text: a door glyph does not say "log out" the way
            // the words do, and this is the one destructive action here.
            Button("Log Out", role: .destructive) {
                session.endSession()
            }
            .accessibilityIdentifier("logoutButton")
        }
    }

    @ViewBuilder
    private var versionSection: some View {
        if let version = AppVersion.displayText {
            Section {
                Text(verbatim: version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
    }
}

#Preview {
    let client = APIClient.makePublicClient(baseURL: "http://localhost:1")
    return BudgetMenuSheet(
        viewModel: BudgetDetailViewModel(
            profile: .with {
                $0.id = "preview-budget"
                $0.name = "Household Budget"
                $0.cycle = .monthly
                $0.countryCode = "US"
            },
            authenticatedClient: client
        ),
        authenticatedClient: client,
        currencyCode: "USD",
        localeIdentifier: "en",
        onUpdated: { _ in },
        onUserUpdated: { _ in },
        onDeleted: {}
    )
    .environment(SessionStore())
}
