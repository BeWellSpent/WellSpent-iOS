import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class PeopleViewModel {
    var newPersonName = ""

    private(set) var isLoading = false
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var incomeSources: [Wellspent_V1_IncomeSource] = []
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let budgetOwnerUserID: String

    private let client: Wellspent_V1_BudgetServiceClient

    var canAddPerson: Bool {
        !newPersonName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(budgetProfileID: String, budgetOwnerUserID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.budgetOwnerUserID = budgetOwnerUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let peopleResponse = client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        async let incomeResponse = client.listIncomeSources(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await peopleResponse.result {
        case .success(let message):
            people = message.people
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load people."
        }

        if case .success(let message) = await incomeResponse.result {
            incomeSources = message.sources
        }
    }

    func addPerson() async {
        guard canAddPerson else { return }
        errorMessage = nil
        let name = newPersonName.trimmingCharacters(in: .whitespaces)

        let request = Wellspent_V1_AddBudgetPeopleRequest.with {
            $0.budgetProfileID = budgetProfileID
            $0.people = [.with { $0.userName = name }]
        }
        let response = await client.addBudgetPeople(request: request)

        switch response.result {
        case .success(let message):
            people.append(contentsOf: message.people)
            newPersonName = ""
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't add that person."
        }
    }

    func updateColor(personID: Int64, color: String) async {
        errorMessage = nil
        let request = Wellspent_V1_UpdateBudgetPersonRequest.with {
            $0.id = personID
            $0.budgetProfileID = budgetProfileID
            $0.color = color
        }
        let response = await client.updateBudgetPerson(request: request)

        switch response.result {
        case .success(let message):
            replace(message.person)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that person's color."
        }
    }

    func updateRole(personID: Int64, role: Wellspent_V1_BudgetRole) async {
        errorMessage = nil
        let request = Wellspent_V1_UpdateBudgetPersonRoleRequest.with {
            $0.personID = personID
            $0.budgetProfileID = budgetProfileID
            $0.role = role
        }
        let response = await client.updateBudgetPersonRole(request: request)

        switch response.result {
        case .success(let message):
            replace(message.person)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't update that person's role."
        }
    }

    func needsReplacement(for person: Wellspent_V1_BudgetPerson) -> Bool {
        PersonReplacement.needsReplacement(person: person, incomeSources: incomeSources)
    }

    @discardableResult
    func remove(personID: Int64, replacementPersonID: Int64) async -> Bool {
        errorMessage = nil
        let request = Wellspent_V1_RemoveBudgetPersonRequest.with {
            $0.budgetProfileID = budgetProfileID
            $0.personID = personID
            $0.replacementPersonID = replacementPersonID
        }
        let response = await client.removeBudgetPerson(request: request)

        switch response.result {
        case .success:
            people.removeAll { $0.id == personID }
            return true
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't remove that person."
            return false
        }
    }

    private func replace(_ person: Wellspent_V1_BudgetPerson) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index] = person
    }
}
