import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class IncomeViewModel {
    private(set) var isLoading = false
    private(set) var sources: [Wellspent_V1_IncomeSource] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var isFree = false
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currentUserID: String?

    private let client: Wellspent_V1_BudgetServiceClient
    private let userClient: Wellspent_V1_UserServiceClient
    private let restClient: WellSpentREST.Client

    /// Free tier caps income sources at 2 per person (`docs/features/tiered-subscriptions.md`).
    /// This budget-wide view can't attribute sources to a specific person by
    /// itself, so it conservatively gates on the *budget's* total source
    /// count — client-side UX polish only, same posture as `AlertsViewModel.isAtLimit`;
    /// the backend enforces the real per-person limit regardless.
    var isAtLimit: Bool {
        isFree && sources.count >= 2
    }

    /// `IncomeSource` already carries `budgetPersonID` on the wire, so this is
    /// a plain equality filter over already-fetched data, not arithmetic —
    /// no backend scoping needed here, unlike `ListTransactions`/`GetExpenseSummary`.
    var visibleSources: [Wellspent_V1_IncomeSource] {
        guard let myPerson = ChartPreference.myPerson(currentUserID: currentUserID, people: people),
              myPerson.focusedViewEnabled else { return sources }
        return sources.filter { FocusedViewFiltering.isMineOrUnattributed($0.budgetPersonID, myPersonID: myPerson.id) }
    }

    init(budgetProfileID: String, currentUserID: String?, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    /// Not private, so `isAtLimit`/`visibleSources` are testable without a
    /// live `GetMe`/`ListBudgetPeople` call.
    func setStateForTesting(sources: [Wellspent_V1_IncomeSource], isFree: Bool, people: [Wellspent_V1_BudgetPerson] = []) {
        self.sources = sources
        self.isFree = isFree
        self.people = people
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let sourcesResult = fetchSources()
        async let peopleResult = fetchPeople()
        async let user = UserRESTMapping.currentUser(connectClient: userClient, restClient: restClient, useREST: FeatureFlags.csharpUserEnabled)

        if let fetched = await sourcesResult {
            sources = fetched
        }

        if let fetched = await peopleResult {
            people = fetched
        }

        if let user = await user {
            isFree = user.plan == .free
        }
    }

    private func fetchSources() async -> [Wellspent_V1_IncomeSource]? {
        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.listIncomeSources(.init(path: .init(id: budgetProfileID)))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load income sources."
                    return nil
                }
                return body.sources.map(BudgetRESTMapping.incomeSource(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load income sources."
                return nil
            }
        }
        let response = await client.listIncomeSources(request: .with { $0.budgetProfileID = budgetProfileID })
        switch response.result {
        case .success(let message):
            return message.sources
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load income sources."
            return nil
        }
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        if FeatureFlags.csharpBudgetEnabled {
            guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID))),
                  case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
            return body.people.map(BudgetRESTMapping.person(from:))
        }
        guard case .success(let message) = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID }).result else {
            return nil
        }
        return message.people
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
        let fallback = "Couldn't delete that income source."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.deleteIncomeSource(.init(path: .init(id: budgetProfileID, sourceId: id))) else {
                    errorMessage = fallback
                    return
                }
                sources.removeAll { $0.id == id }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

        let request = Wellspent_V1_DeleteIncomeSourceRequest.with {
            $0.id = id
            $0.budgetProfileID = budgetProfileID
        }
        let response = await client.deleteIncomeSource(request: request)

        switch response.result {
        case .success:
            sources.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? fallback
        }
    }
}
