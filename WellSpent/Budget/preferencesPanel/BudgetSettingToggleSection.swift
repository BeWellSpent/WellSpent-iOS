import SwiftUI
import WellSpentAPI

/// A budget-wide, Admin-only boolean setting.
///
/// Extracted rather than copied: the carryover and plan-follows-paid settings
/// are the same section down to the optimistic update and rollback.
/// Deliberately separate from the per-person chart preferences above them,
/// which are intentionally not role-gated — these change what every member of
/// the budget gets.
struct BudgetSettingToggleSection: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient?
    let header: LocalizedStringKey
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    let accessibilityID: String
    let read: (Wellspent_V1_BudgetProfile) -> Bool
    let write: (Wellspent_V1_BudgetServiceClient, String, Bool) async -> String?

    @Environment(SessionStore.self) private var session
    @State private var viewModel: BudgetSettingToggleViewModel?

    var body: some View {
        Group {
            if let viewModel {
                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { newValue in Task { await viewModel.update(enabled: newValue) } }
                    )) {
                        Text(title)
                    }
                    .disabled(!viewModel.isAdmin || viewModel.isSaving || viewModel.isLoading)
                    .accessibilityIdentifier(accessibilityID)

                    if !viewModel.isAdmin {
                        Text("Only a budget admin can change this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(header)
                } footer: {
                    Text(footer)
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
                viewModel = BudgetSettingToggleViewModel(
                    budgetProfileID: budgetProfileID,
                    currentUserID: session.userID,
                    authenticatedClient: authenticatedClient,
                    read: read,
                    write: write
                )
            }
            await viewModel?.load()
        }
    }
}
