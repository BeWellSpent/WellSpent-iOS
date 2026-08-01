import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("BudgetRoleResolver")
struct BudgetRoleResolverTests {
    private func person(userID: String, role: Wellspent_V1_BudgetRole) -> Wellspent_V1_BudgetPerson {
        .with { $0.userID = userID; $0.role = role }
    }

    @Test("owner always resolves to admin regardless of any matching person")
    func ownerAlwaysAdmin() {
        let role = BudgetRoleResolver.role(
            currentUserID: "owner-1",
            budgetOwnerUserID: "owner-1",
            people: [person(userID: "owner-1", role: .viewer)]
        )
        #expect(role == .admin)
    }

    @Test("non-owner resolves to their matched BudgetPerson's role")
    func matchedPersonRole() {
        let role = BudgetRoleResolver.role(
            currentUserID: "user-2",
            budgetOwnerUserID: "owner-1",
            people: [person(userID: "user-2", role: .collaborator)]
        )
        #expect(role == .collaborator)
    }

    @Test("unmatched user resolves to unspecified")
    func unmatchedUserIsUnspecified() {
        let role = BudgetRoleResolver.role(
            currentUserID: "stranger",
            budgetOwnerUserID: "owner-1",
            people: [person(userID: "user-2", role: .collaborator)]
        )
        #expect(role == .unspecified)
    }

    @Test("nil or empty currentUserID resolves to unspecified")
    func nilOrEmptyUserIDIsUnspecified() {
        #expect(BudgetRoleResolver.role(currentUserID: nil, budgetOwnerUserID: "owner-1", people: []) == .unspecified)
        #expect(BudgetRoleResolver.role(currentUserID: "", budgetOwnerUserID: "owner-1", people: []) == .unspecified)
    }

    @Test("canEdit and canManageUsers truth table across all roles")
    func permissionTruthTable() {
        #expect(BudgetRoleResolver.canEdit(.admin) == true)
        #expect(BudgetRoleResolver.canEdit(.collaborator) == true)
        #expect(BudgetRoleResolver.canEdit(.viewer) == false)
        #expect(BudgetRoleResolver.canEdit(.unspecified) == false)

        #expect(BudgetRoleResolver.canManageUsers(.admin) == true)
        #expect(BudgetRoleResolver.canManageUsers(.collaborator) == false)
        #expect(BudgetRoleResolver.canManageUsers(.viewer) == false)
        #expect(BudgetRoleResolver.canManageUsers(.unspecified) == false)
    }
}
