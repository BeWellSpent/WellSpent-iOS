import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("InvitesViewModel")
@MainActor
struct InvitesViewModelTests {
    private func makeViewModel(budgetOwnerUserID: String, currentUserID: String?) -> InvitesViewModel {
        InvitesViewModel(
            budgetProfileID: "profile-1",
            budgetOwnerUserID: budgetOwnerUserID,
            currentUserID: currentUserID,
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("the budget owner is always admin")
    func ownerIsAlwaysAdmin() {
        let viewModel = makeViewModel(budgetOwnerUserID: "user-1", currentUserID: "user-1")
        #expect(viewModel.isAdmin)
    }

    @Test("a linked member with the admin role is admin")
    func linkedAdminMemberIsAdmin() {
        let viewModel = makeViewModel(budgetOwnerUserID: "owner-1", currentUserID: "user-2")
        viewModel.setPeopleForTesting([
            .with { $0.userID = "user-2"; $0.role = .admin }
        ])
        #expect(viewModel.isAdmin)
    }

    @Test("a linked collaborator or viewer is not admin")
    func linkedNonAdminMemberIsNotAdmin() {
        let viewModel = makeViewModel(budgetOwnerUserID: "owner-1", currentUserID: "user-2")
        viewModel.setPeopleForTesting([
            .with { $0.userID = "user-2"; $0.role = .collaborator }
        ])
        #expect(!viewModel.isAdmin)
    }

    @Test("no matching person and not the owner is not admin")
    func unrelatedUserIsNotAdmin() {
        let viewModel = makeViewModel(budgetOwnerUserID: "owner-1", currentUserID: "user-3")
        #expect(!viewModel.isAdmin)
    }

    @Test("a nil current user (unauthenticated) is not admin")
    func nilCurrentUserIsNotAdmin() {
        let viewModel = makeViewModel(budgetOwnerUserID: "owner-1", currentUserID: nil)
        #expect(!viewModel.isAdmin)
    }
}
