import Foundation
import Observation
import WellSpentAPI

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

    private let client: Wellspent_V1_BudgetServiceClient

    var totalText: String {
        TransactionAmountFormatting.totalDisplayText(
            amounts: sources.map { (units: $0.amount.units, nanos: $0.amount.nanos) },
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }

    init(budgetProfileID: String, currencyCode: String, localeIdentifier: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.localeIdentifier = localeIdentifier
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let sourcesResponse = client.listSavingsSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let paymentMethodsResponse = client.listPaymentMethods(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await sourcesResponse.result {
        case .success(let message):
            sources = message.sources
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load savings."
        }

        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
        if case .success(let message) = await paymentMethodsResponse.result {
            paymentMethods = message.methods
        }
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
        let request = Wellspent_V1_DeleteSavingsSourceRequest.with {
            $0.id = id
            $0.budgetProfileID = budgetProfileID
        }
        let response = await client.deleteSavingsSource(request: request)

        switch response.result {
        case .success:
            sources.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that savings source."
        }
    }
}
