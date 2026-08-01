import Observation
import WellSpentAPI

@MainActor
@Observable
final class ReportsPlaceholderViewModel {
    private(set) var isFree = false

    private let userClient: Wellspent_V1_UserServiceClient

    init(authenticatedClient: ProtocolClient) {
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
    }

    func load() async {
        let response = await userClient.getMe(request: Wellspent_V1_GetMeRequest())
        if case .success(let message) = response.result {
            isFree = message.user.plan == .free || message.user.plan == .unspecified
        }
    }
}
