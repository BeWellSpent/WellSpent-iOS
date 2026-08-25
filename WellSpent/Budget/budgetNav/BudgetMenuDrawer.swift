import Foundation
import SwiftUI
import WellSpentAPI

/// Where the ☰ can take you. Presented over the whole screen rather than
/// pushed inside the drawer: the drawer is ~320pt wide, which is the wrong
/// place to render Settings or the manage panels. Web's drawer behaves the
/// same way — it closes, and the main content navigates.
enum BudgetMenuDestination: Int, Identifiable {
    case manage
    case settings
    case help
    case allPeriods

    var id: Int { rawValue }
}

/// Contents of the left navigation drawer: which period you are looking at,
/// and everything that is not one of the four bottom tabs.
///
/// It selects and closes — it does not navigate. `BudgetDetailView` owns the
/// presentation, so a destination opens at full width instead of inside the
/// panel. See docs/features/main-view-rework.md.
///
/// The period section lists only the current period's own year. A budget
/// gains twelve periods a year forever, so the full history is its own
/// destination.
struct BudgetMenuDrawer: View {
    @Environment(SessionStore.self) private var session

    let viewModel: BudgetDetailViewModel
    let localeIdentifier: String
    let onSelect: (BudgetMenuDestination) -> Void
    let onSelectPeriod: (String) -> Void
    let onClose: () -> Void

    private var periodsThisYear: [Wellspent_V1_BudgetPeriod] {
        guard let current = viewModel.currentPeriod else { return [] }
        let year = Calendar.current.component(.year, from: current.startDate.dateOnly)
        return viewModel.periods.filter {
            Calendar.current.component(.year, from: $0.startDate.dateOnly) == year
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                periodSection
                destinationsSection
                logoutSection
                versionSection
            }
            .listStyle(.insetGrouped)
        }
    }

    private var header: some View {
        HStack {
            Text(viewModel.profile.name)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            SheetCancelButton(action: onClose)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var periodSection: some View {
        Section("Period") {
            ForEach(periodsThisYear, id: \.id) { period in
                Button {
                    onSelectPeriod(period.id)
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

            row("View all periods", systemImage: "calendar", identifier: "viewAllPeriodsLink") {
                onSelect(.allPeriods)
            }
        }
    }

    @ViewBuilder
    private var destinationsSection: some View {
        Section {
            row("Manage budget", systemImage: "slider.horizontal.3", identifier: "manageBudgetLink") {
                onSelect(.manage)
            }
            row("Settings", systemImage: "gearshape", identifier: "settingsButton") {
                onSelect(.settings)
            }
            // A shortcut to what Settings' own Help section holds, not a
            // second copy of it — issue #60 asks for Help to be reachable
            // from this menu directly.
            row("Help", systemImage: "questionmark.circle", identifier: "helpLink") {
                onSelect(.help)
            }
        }
    }

    private var logoutSection: some View {
        Section {
            // Keeps its text: a door glyph does not say "log out" the way the
            // words do, and this is the one destructive action here.
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

    private func row(
        _ title: LocalizedStringKey,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
        }
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    let client = APIClient.makePublicClient(baseURL: "http://localhost:1")
    return BudgetMenuDrawer(
        viewModel: BudgetDetailViewModel(
            profile: .with {
                $0.id = "preview-budget"
                $0.name = "Household Budget"
                $0.cycle = .monthly
                $0.countryCode = "US"
            },
            authenticatedClient: client
        ),
        localeIdentifier: "en",
        onSelect: { _ in },
        onSelectPeriod: { _ in },
        onClose: {}
    )
    .environment(SessionStore())
}
