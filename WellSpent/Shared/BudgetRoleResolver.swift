import WellSpentAPI

/// Mirrors web's `useBudgetRole`: the budget profile owner is always Admin;
/// otherwise resolved from the matching linked `BudgetPerson`'s role.
nonisolated enum BudgetRoleResolver {
    static func role(currentUserID: String?, budgetOwnerUserID: String, people: [Wellspent_V1_BudgetPerson]) -> Wellspent_V1_BudgetRole {
        guard let currentUserID, !currentUserID.isEmpty else { return .unspecified }
        if currentUserID == budgetOwnerUserID { return .admin }
        return people.first(where: { !$0.userID.isEmpty && $0.userID == currentUserID })?.role ?? .unspecified
    }

    static func canEdit(_ role: Wellspent_V1_BudgetRole) -> Bool {
        role == .admin || role == .collaborator
    }

    static func canManageUsers(_ role: Wellspent_V1_BudgetRole) -> Bool {
        role == .admin
    }
}
