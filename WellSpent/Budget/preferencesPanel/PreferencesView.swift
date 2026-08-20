import SwiftUI
import WellSpentAPI

/// Per-person settings for one budget. Deliberately not role-gated: these are
/// the caller's own view preferences, so a Viewer changes theirs like anyone
/// else. The RPC takes no person id, so nothing here can edit someone else's.
struct PreferencesView: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient?

    @Environment(SessionStore.self) private var session
    @State private var viewModel: PreferencesViewModel?

    var body: some View {
        List {
            if let viewModel {
                if viewModel.isLoading {
                    ProgressView()
                } else if !viewModel.isLinkedMember {
                    Text("Preferences are available once you're linked to this budget.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        chartPicker(
                            title: "Expense Plan chart",
                            caption: "Shown on the Expense Plan tab, above your planned amounts.",
                            selection: viewModel.planChart,
                            identifier: "planChartPreference"
                        ) { newValue in
                            Task { await viewModel.update(plan: newValue, overview: viewModel.overviewChart) }
                        }

                        chartPicker(
                            title: "Expense Overview chart",
                            caption: "Shown on the Expense Overview tab, above what you actually spent.",
                            selection: viewModel.overviewChart,
                            identifier: "overviewChartPreference"
                        ) { newValue in
                            Task { await viewModel.update(plan: viewModel.planChart, overview: newValue) }
                        }
                    } header: {
                        Text("Charts")
                    } footer: {
                        Text("These settings are yours alone — other people on this budget keep their own.")
                    }
                    .disabled(viewModel.isSaving)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                // Budget-wide, Admin only — unlike the per-person settings above.
                BudgetSettingsSections(
                    budgetProfileID: budgetProfileID,
                    authenticatedClient: authenticatedClient
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Preferences")
        .task {
            guard let authenticatedClient else { return }
            if viewModel == nil {
                viewModel = PreferencesViewModel(
                    budgetProfileID: budgetProfileID,
                    currentUserID: session.userID,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
    }

    /// The label is drawn above the control rather than passed to `Picker`:
    /// `.segmented` discards a picker's own label, which left two unlabelled
    /// controls stacked with nothing saying which tab each belonged to.
    private func chartPicker(
        title: LocalizedStringKey,
        caption: LocalizedStringKey,
        selection: ExpenseChartView.ChartType,
        identifier: String,
        onChange: @escaping (ExpenseChartView.ChartType) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: Binding(
                get: { selection },
                set: { onChange($0) }
            )) {
                Label("Pie", systemImage: "chart.pie").tag(ExpenseChartView.ChartType.pie)
                Label("Bar", systemImage: "chart.bar").tag(ExpenseChartView.ChartType.bar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 4)
    }
}
