import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("BudgetRoleLabel")
struct BudgetRoleLabelTests {
    private static let knownRoles: [Wellspent_V1_BudgetRole] = [.unspecified, .admin, .collaborator, .viewer]

    @Test("every known role maps to a non-empty label", arguments: knownRoles)
    func labelsAreNonEmpty(role: Wellspent_V1_BudgetRole) {
        #expect(!BudgetRoleLabel.text(for: role).isEmpty)
    }

    @Test("known roles map to distinct labels")
    func labelsAreDistinct() {
        let labels = Set(Self.knownRoles.map { BudgetRoleLabel.text(for: $0) })
        #expect(labels.count == Self.knownRoles.count)
    }
}
