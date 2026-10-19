import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class ReportsPlaceholderViewModel {
    private(set) var isFree = false

    private let restClient: WellSpentREST.Client

    init(restClient: WellSpentREST.Client) {
        self.restClient = restClient
    }

    func load() async {
        guard let user = await UserRESTMapping.currentUser(restClient: restClient) else { return }
        isFree = user.plan == .free || user.plan == .unspecified
    }
}
