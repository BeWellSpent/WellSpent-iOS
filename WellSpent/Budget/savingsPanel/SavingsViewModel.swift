import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class SavingsViewModel {
    private(set) var isLoading = false
    private(set) var sources: [Wellspent_V1_SavingsSource] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let currentUserID: String?

    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    /// `SavingsSource` already carries `budgetPersonID` on the wire, so this
    /// is a plain equality filter over already-fetched data, not arithmetic —
    /// no backend scoping needed here, unlike `ListTransactions`/`GetExpenseSummary`.
    var visibleSources: [Wellspent_V1_SavingsSource] {
        guard let myPerson = ChartPreference.myPerson(currentUserID: currentUserID, people: people),
              myPerson.focusedViewEnabled else { return sources }
        return sources.filter { FocusedViewFiltering.isMineOrUnattributed($0.budgetPersonID, myPersonID: myPerson.id) }
    }

    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: visibleSources.map { (units: $0.amount.units, nanos: $0.amount.nanos) },
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }

    init(budgetProfileID: String, currencyCode: String, localeIdentifier: String, currentUserID: String?, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let sourcesResult = fetchSources()
        async let peopleResult = fetchPeople()
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })

        if let fetched = await sourcesResult {
            sources = fetched
        }

        if let fetched = await peopleResult {
            people = fetched
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
    }

    private func fetchSources() async -> [Wellspent_V1_SavingsSource]? {
        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.listSavingsSources(.init(path: .init(id: budgetProfileID)))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load savings."
                    return nil
                }
                return body.sources.map(BudgetRESTMapping.savingsSource(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load savings."
                return nil
            }
        }
        let response = await client.listSavingsSources(request: .with { $0.budgetProfileID = budgetProfileID })
        switch response.result {
        case .success(let message):
            return message.sources
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load savings."
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

    func personName(for personID: Int64) -> String? {
        guard personID != 0 else { return nil }
        return people.first(where: { $0.id == personID })?.userName
    }

    func personColor(for personID: Int64) -> String {
        people.first(where: { $0.id == personID })?.color ?? ""
    }

    func paymentMethodName(for paymentMethodID: String) -> String? {
        guard !paymentMethodID.isEmpty else { return nil }
        guard let method = paymentMethods.first(where: { $0.id == paymentMethodID }) else { return nil }
        return method.alias.isEmpty ? method.name : method.alias
    }

    func paymentMethodColor(for paymentMethodID: String) -> String {
        paymentMethods.first(where: { $0.id == paymentMethodID })?.color ?? ""
    }

    /// Not private, so `visibleSources` is testable without a live
    /// `ListSavingsSources`/`ListBudgetPeople` call.
    func setStateForTesting(sources: [Wellspent_V1_SavingsSource], people: [Wellspent_V1_BudgetPerson] = []) {
        self.sources = sources
        self.people = people
    }

    func addSource(_ source: Wellspent_V1_SavingsSource) {
        sources.append(source)
    }

    func replaceSource(_ source: Wellspent_V1_SavingsSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
    }

    /// Plain delete, no replacement — savings sources aren't referenced by
    /// other rows the way payment methods/categories are.
    func delete(id: Int64) async {
        errorMessage = nil
        let fallback = "Couldn't delete that savings source."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.deleteSavingsSource(.init(path: .init(id: budgetProfileID, sourceId: id))) else {
                    errorMessage = fallback
                    return
                }
                sources.removeAll { $0.id == id }
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

        let request = Wellspent_V1_DeleteSavingsSourceRequest.with {
            $0.id = id
            $0.budgetProfileID = budgetProfileID
        }
        let response = await client.deleteSavingsSource(request: request)

        switch response.result {
        case .success:
            sources.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? fallback
        }
    }
}
