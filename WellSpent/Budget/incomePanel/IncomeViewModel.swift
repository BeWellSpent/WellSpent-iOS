import Observation
import WellSpentAPI

@MainActor
@Observable
final class IncomeViewModel {
    private(set) var isLoading = false
    private(set) var sources: [Wellspent_V1_IncomeSource] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient

    init(budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let sourcesResponse = client.listIncomeSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await sourcesResponse.result {
        case .success(let message):
            sources = message.sources
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load income sources."
        }

        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
    }

    func personName(for budgetPersonID: Int64) -> String? {
        guard budgetPersonID != 0 else { return nil }
        return people.first(where: { $0.id == budgetPersonID })?.userName
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
