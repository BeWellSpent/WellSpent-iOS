import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class PeopleViewModel {
    var newPersonName = ""

    private(set) var isLoading = false
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var incomeSources: [Wellspent_V1_IncomeSource] = []
    private(set) var isFree = false
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let budgetOwnerUserID: String

    private let client: Wellspent_V1_BudgetServiceClient
    private let userClient: Wellspent_V1_UserServiceClient
    private let restClient: WellSpentREST.Client

    var canAddPerson: Bool {
        !newPersonName.trimmingCharacters(in: .whitespaces).isEmpty && !isAtLimit
    }

    /// Free tier caps active people at 2 (`docs/features/tiered-subscriptions.md`)
    /// — client-side UX polish only, the backend is the real enforcement
    /// boundary (same posture as `AlertsViewModel.isAtLimit`).
    var isAtLimit: Bool {
        isFree && people.count >= 2
    }

    init(budgetProfileID: String, budgetOwnerUserID: String, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.budgetOwnerUserID = budgetOwnerUserID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    /// Not private, so `isAtLimit` is testable without a live `GetMe` call.
    func setStateForTesting(people: [Wellspent_V1_BudgetPerson], isFree: Bool) {
        self.people = people
        self.isFree = isFree
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let peopleResult = fetchPeople()
        async let incomeResponse = client.listIncomeSources(request: .with { $0.budgetProfileID = budgetProfileID })
        async let user = UserRESTMapping.currentUser(connectClient: userClient, restClient: restClient, useREST: FeatureFlags.csharpUserEnabled)

        if let fetched = await peopleResult {
            people = fetched
        }

        if case .success(let message) = await incomeResponse.result {
            incomeSources = message.sources
        }

        if let user = await user {
            isFree = user.plan == .free
        }
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.listBudgetPeople(.init(path: .init(id: budgetProfileID)))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load people."
                    return nil
                }
                return body.people.map(BudgetRESTMapping.person(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load people."
                return nil
            }
        }
        let response = await client.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })
        switch response.result {
        case .success(let message):
            return message.people
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load people."
            return nil
        }
    }

    func addPerson() async {
        guard canAddPerson else { return }
        errorMessage = nil
        let name = newPersonName.trimmingCharacters(in: .whitespaces)
        let fallback = "Couldn't add that person."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.addBudgetPeople(.init(
                    path: .init(id: budgetProfileID),
                    body: .json(.init(people: [.init(userName: name)]))
                ))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = fallback
                    return
                }
                people.append(contentsOf: body.people.map(BudgetRESTMapping.person(from:)))
                newPersonName = ""
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

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
            errorMessage = error.message ?? fallback
        }
    }

    func updateColor(personID: Int64, color: String) async {
        errorMessage = nil
        let fallback = "Couldn't update that person's color."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.updateBudgetPerson(.init(
                    path: .init(id: budgetProfileID, personId: personID),
                    body: .json(.init(color: color))
                ))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = fallback
                    return
                }
                replace(BudgetRESTMapping.person(from: body.person))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

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
            errorMessage = error.message ?? fallback
        }
    }

    func updateRole(personID: Int64, role: Wellspent_V1_BudgetRole) async {
        errorMessage = nil
        let fallback = "Couldn't update that person's role."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.updateBudgetPersonRole(.init(
                    path: .init(id: budgetProfileID, personId: personID),
                    body: .json(.init(role: BudgetRESTMapping.restSendRole(from: role)))
                ))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = fallback
                    return
                }
                replace(BudgetRESTMapping.person(from: body.person))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

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
            errorMessage = error.message ?? fallback
        }
    }

    func needsReplacement(for person: Wellspent_V1_BudgetPerson) -> Bool {
        PersonReplacement.needsReplacement(person: person, incomeSources: incomeSources)
    }

    @discardableResult
    func remove(personID: Int64, replacementPersonID: Int64) async -> Bool {
        errorMessage = nil
        let fallback = "Couldn't remove that person."

        if FeatureFlags.csharpBudgetEnabled {
            do {
                guard case .ok = try await restClient.removeBudgetPerson(.init(
                    path: .init(id: budgetProfileID, personId: personID),
                    query: .init(replacementPersonId: replacementPersonID == 0 ? nil : replacementPersonID)
                )) else {
                    errorMessage = fallback
                    return false
                }
                people.removeAll { $0.id == personID }
                return true
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                return false
            }
        }

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
            errorMessage = error.message ?? fallback
            return false
        }
    }

    private func replace(_ person: Wellspent_V1_BudgetPerson) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index] = person
    }
}
