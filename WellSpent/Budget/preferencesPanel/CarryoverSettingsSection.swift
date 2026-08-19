import SwiftUI
import WellSpentAPI

/// The budget's carryover toggle, shown beneath the per-person chart settings.
///
/// The footer spells the rule out rather than saying "carry my balance
/// forward". Nothing else in the app creates transactions on the user's behalf,
/// so a switch that silently does needs to say what it will produce.
struct CarryoverSettingsSection: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient?

    @Environment(SessionStore.self) private var session
    @State private var viewModel: CarryoverSettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { newValue in Task { await viewModel.update(enabled: newValue) } }
                    )) {
                        Text("Carry balance forward")
                    }
                    .disabled(!viewModel.isAdmin || viewModel.isSaving || viewModel.isLoading)
                    .accessibilityIdentifier("carryoverToggle")

                    if !viewModel.isAdmin {
                        Text("Only a budget admin can change this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Balance")
                } footer: {
                    Text("When a period ends, roll its balance into the next one. Money left over is added to Savings; if you overspent, the shortfall is split across the payment methods you spent it on, so the debt shows where it came from.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
        }
        .task {
            guard let authenticatedClient else { return }
            if viewModel == nil {
                viewModel = CarryoverSettingsViewModel(
                    budgetProfileID: budgetProfileID,
                    currentUserID: session.userID,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
    }
}
