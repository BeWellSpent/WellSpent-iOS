import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class ReportsPlaceholderViewModel {
    private(set) var isFree = false

    private let userClient: Wellspent_V1_UserServiceClient
    private let restClient: WellSpentREST.Client

    init(authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func load() async {
        guard let user = await UserRESTMapping.currentUser(connectClient: userClient, restClient: restClient, useREST: FeatureFlags.csharpUserEnabled) else { return }
        isFree = user.plan == .free || user.plan == .unspecified
    }
}
