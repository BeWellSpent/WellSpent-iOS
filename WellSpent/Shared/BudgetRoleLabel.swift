import WellSpentAPI

/// Display text for a `BudgetRole`. Mirrors web's `useRoleLabel` hook
/// (`WellSpent-web/src/components/budget/peoplePanel/useRoleLabel.ts`).
nonisolated enum BudgetRoleLabel {
    static func text(for role: Wellspent_V1_BudgetRole) -> String {
        switch role {
        case .unspecified:
            return "No account"
        case .admin:
            return "Admin"
        case .collaborator:
            return "Collaborator"
        case .viewer:
            return "Viewer"
        case .UNRECOGNIZED:
            return "Unknown"
        }
    }
}
