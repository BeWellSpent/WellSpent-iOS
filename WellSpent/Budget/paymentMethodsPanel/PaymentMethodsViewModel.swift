import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class PaymentMethodsViewModel {
    private(set) var isLoading = false
    private(set) var methods: [Wellspent_V1_PaymentMethod] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    /// A budget needs at least one payment method to reassign to when
    /// deleting another, matching web's rule.
    var canDelete: Bool {
        methods.count > 1
    }

    init(budgetProfileID: String, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let methodsResult = fetchMethods()
        async let peopleResult = fetchPeople()

        if let fetched = await methodsResult {
            methods = fetched
        }

        if let fetched = await peopleResult {
            people = fetched
        }
    }

    private func fetchMethods() async -> [Wellspent_V1_PaymentMethod]? {
        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.listPaymentMethods(.init(path: .init(id: budgetProfileID)))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load payment methods."
                    return nil
                }
                return body.methods.map(BudgetRESTMapping.paymentMethod(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load payment methods."
                return nil
            }
        }
        let response = await client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })
        switch response.result {
        case .success(let message):
            return message.methods
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load payment methods."
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

    func addMethod(_ method: Wellspent_V1_PaymentMethod) {
        methods.append(method)
    }

    func replaceMethod(_ method: Wellspent_V1_PaymentMethod) {
        guard let index = methods.firstIndex(where: { $0.id == method.id }) else { return }
        methods[index] = method
    }

    @discardableResult
    func delete(id: String, replacementID: String) async -> Bool {
        errorMessage = nil
        let fallback = "Couldn't delete that payment method."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.deletePaymentMethod(.init(
                    path: .init(id: id),
                    query: .init(replacementId: replacementID, budgetProfileId: budgetProfileID)
                )) else {
                    errorMessage = fallback
                    return false
                }
                methods.removeAll { $0.id == id }
                return true
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                return false
            }
        }

        let request = Wellspent_V1_DeletePaymentMethodRequest.with {
            $0.id = id
            $0.replacementID = replacementID
            $0.budgetProfileID = budgetProfileID
        }
        let response = await client.deletePaymentMethod(request: request)

        switch response.result {
        case .success:
            methods.removeAll { $0.id == id }
            return true
        case .failure(let error):
            errorMessage = error.message ?? fallback
            return false
        }
    }
}
