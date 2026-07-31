import Observation
import WellSpentAPI

@MainActor
@Observable
final class PaymentMethodsViewModel {
    private(set) var isLoading = false
    private(set) var methods: [Wellspent_V1_PaymentMethod] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let client: Wellspent_V1_BudgetServiceClient

    /// A budget needs at least one payment method to reassign to when
    /// deleting another, matching web's rule.
    var canDelete: Bool {
        methods.count > 1
    }

    init(budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let methodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await methodsResponse.result {
        case .success(let message):
            methods = message.methods
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load payment methods."
        }

        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
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
            errorMessage = error.message ?? "Couldn't delete that payment method."
            return false
        }
    }
}
