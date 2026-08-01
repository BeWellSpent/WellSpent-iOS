import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AcceptInviteViewModel")
@MainActor
struct AcceptInviteViewModelTests {
    @Test("accept() is a no-op guard when authenticatedClient is nil")
    func acceptGuardsWhenUnauthenticated() async {
        let viewModel = AcceptInviteViewModel(
            token: "preview-token",
            publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            authenticatedClient: nil
        )

        await viewModel.accept()

        #expect(viewModel.acceptedBudgetProfileID == nil)
        #expect(viewModel.isAccepting == false)
        #expect(viewModel.errorMessage == nil)
    }
}
