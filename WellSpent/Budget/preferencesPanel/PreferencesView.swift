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
                            selection: viewModel.planChart,
                            identifier: "planChartPreference"
                        ) { newValue in
                            Task { await viewModel.update(plan: newValue, overview: viewModel.overviewChart) }
                        }

                        chartPicker(
                            title: "Expense Overview chart",
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

    private func chartPicker(
        title: LocalizedStringKey,
        selection: ExpenseChartView.ChartType,
        identifier: String,
        onChange: @escaping (ExpenseChartView.ChartType) -> Void
    ) -> some View {
        Picker(title, selection: Binding(
            get: { selection },
            set: { onChange($0) }
        )) {
            Text("Pie").tag(ExpenseChartView.ChartType.pie)
            Text("Bar").tag(ExpenseChartView.ChartType.bar)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(identifier)
    }
}
