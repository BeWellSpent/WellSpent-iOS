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

    /// The Section is rendered unconditionally, with the toggle simply disabled
    /// until the view model loads.
    ///
    /// It must never resolve to empty content: a `List` only materialises rows
    /// that actually produce something, so a view gated on `if let viewModel`
    /// never becomes a row, never "appears", and therefore never runs the
    /// `.task` that would have created that view model — the section stays
    /// invisible forever. That deadlock is exactly what hid both budget
    /// settings until it was found live.
    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel?.isEnabled ?? false },
                set: { newValue in
                    guard let viewModel else { return }
                    Task { await viewModel.update(enabled: newValue) }
                }
            )) {
                Text(title)
            }
            .disabled(!canToggle)
            .accessibilityIdentifier(accessibilityID)

            if let viewModel, !viewModel.isLoading, !viewModel.isAdmin {
                Text("Only a budget admin can change this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel?.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
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

    private var canToggle: Bool {
        guard let viewModel else { return false }
        return viewModel.isAdmin && !viewModel.isSaving && !viewModel.isLoading
    }
}
