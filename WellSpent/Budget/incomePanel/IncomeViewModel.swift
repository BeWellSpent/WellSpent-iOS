import Observation
import WellSpentAPI

@MainActor
@Observable
final class IncomeViewModel {
    private(set) var isLoading = false
    private(set) var sources: [Wellspent_V1_IncomeSource] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var isFree = false
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient
    private let userClient: Wellspent_V1_UserServiceClient

    /// Free tier caps income sources at 2 per person (`docs/features/tiered-subscriptions.md`).
    /// This budget-wide view can't attribute sources to a specific person by
    /// itself, so it conservatively gates on the *budget's* total source
    /// count — client-side UX polish only, same posture as `AlertsViewModel.isAtLimit`;
    /// the backend enforces the real per-person limit regardless.
    var isAtLimit: Bool {
        isFree && sources.count >= 2
    }

    init(budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
    }

    /// Not private, so `isAtLimit` is testable without a live `GetMe` call.
    func setStateForTesting(sources: [Wellspent_V1_IncomeSource], isFree: Bool) {
        self.sources = sources
        self.isFree = isFree
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let sourcesResponse = client.listIncomeSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let meResponse = userClient.getMe(request: Wellspent_V1_GetMeRequest())

        switch await sourcesResponse.result {
        case .success(let message):
            sources = message.sources
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load income sources."
        }

        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }

        if case .success(let message) = await meResponse.result {
            isFree = message.user.plan == .free
        }
    }

    func personName(for budgetPersonID: Int64) -> String? {
        guard budgetPersonID != 0 else { return nil }
        return people.first(where: { $0.id == budgetPersonID })?.userName
    }

    func personColor(for budgetPersonID: Int64) -> String {
        people.first(where: { $0.id == budgetPersonID })?.color ?? ""
    }

    func addSource(_ source: Wellspent_V1_IncomeSource) {
        sources.append(source)
    }

    func replaceSource(_ source: Wellspent_V1_IncomeSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
    }

    func delete(id: Int64) async {
        errorMessage = nil
        let request = Wellspent_V1_DeleteIncomeSourceRequest.with {
            $0.id = id
            $0.budgetProfileID = budgetProfileID
        }
        let response = await client.deleteIncomeSource(request: request)

        switch response.result {
        case .success:
            sources.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that income source."
        }
    }
}
