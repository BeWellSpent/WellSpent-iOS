import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class InvitesViewModel {
    var draftEmail = ""
    var draftRole: Wellspent_V1_BudgetRole = .collaborator
    var draftBudgetPersonID: Int64 = 0

    private(set) var isLoading = false
    private(set) var invites: [Wellspent_V1_BudgetInvite] = []
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var isSending = false
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let budgetOwnerUserID: String
    let currentUserID: String?

    private let client: Wellspent_V1_InviteServiceClient
    private let budgetClient: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    var isAdmin: Bool {
        BudgetRoleResolver.canManageUsers(
            BudgetRoleResolver.role(currentUserID: currentUserID, budgetOwnerUserID: budgetOwnerUserID, people: people)
        )
    }

    /// Budget people with no linked user account yet — offered as the
    /// optional "link to an existing placeholder" picker when sending.
    var guestPeople: [Wellspent_V1_BudgetPerson] {
        people.filter { $0.userID.isEmpty }
    }

    var visibleInvites: [Wellspent_V1_BudgetInvite] {
        InviteListCalculations.latestPerEmail(invites)
    }

    var canSend: Bool {
        !draftEmail.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    init(budgetProfileID: String, budgetOwnerUserID: String, currentUserID: String?, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.budgetOwnerUserID = budgetOwnerUserID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_InviteServiceClient(client: authenticatedClient)
        self.budgetClient = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    /// Not private, so `isAdmin` is testable without a live `ListBudgetPeople`
    /// call — mirrors `SettingsViewModel.apply` being internal for the same reason.
    func setPeopleForTesting(_ people: [Wellspent_V1_BudgetPerson]) {
        self.people = people
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let invitesResult = fetchInvites()
        async let peopleResponse = budgetClient.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })

        if let fetched = await invitesResult {
            invites = fetched
        }

        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
    }

    private func fetchInvites() async -> [Wellspent_V1_BudgetInvite]? {
        if FeatureFlags.csharpInviteEnabled {
            do {
                let output = try await restClient.listBudgetInvites(.init(query: .init(budgetProfileId: budgetProfileID)))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load invites."
                    return nil
                }
                return body.invites.map(InviteRESTMapping.invite(from:))
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load invites."
                return nil
            }
        }
        let response = await client.listBudgetInvites(request: .with { $0.budgetProfileID = budgetProfileID })
        switch response.result {
        case .success(let message):
            return message.invites
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load invites."
            return nil
        }
    }

    func send() async {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        if FeatureFlags.csharpInviteEnabled {
            guard let invite = await sendInviteViaREST(email: draftEmail.trimmingCharacters(in: .whitespaces), role: draftRole, budgetPersonID: draftBudgetPersonID, fallback: "Couldn't send that invite.") else { return }
            invites.append(invite)
            draftEmail = ""
            draftRole = .collaborator
            draftBudgetPersonID = 0
            return
        }

        let response = await client.sendBudgetInvite(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.email = draftEmail.trimmingCharacters(in: .whitespaces)
            $0.role = draftRole
            $0.budgetPersonID = draftBudgetPersonID
        })

        switch response.result {
        case .success(let message):
            invites.append(message.invite)
            draftEmail = ""
            draftRole = .collaborator
            draftBudgetPersonID = 0
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't send that invite."
        }
    }

    private func sendInviteViaREST(email: String, role: Wellspent_V1_BudgetRole, budgetPersonID: Int64, fallback: String) async -> Wellspent_V1_BudgetInvite? {
        do {
            let output = try await restClient.sendBudgetInvite(.init(body: .json(.init(
                budgetProfileId: budgetProfileID,
                email: email,
                role: InviteRESTMapping.sendRole(from: role),
                budgetPersonId: budgetPersonID == 0 ? nil : budgetPersonID
            ))))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                return nil
            }
            return InviteRESTMapping.invite(from: body.invite)
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return nil
        }
    }

    private func cancelInviteViaREST(id: String, fallback: String) async -> Bool {
        do {
            guard case .ok = try await restClient.cancelBudgetInvite(.init(path: .init(id: id))) else {
                errorMessage = fallback
                return false
            }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }

    func cancel(id: String) async {
        errorMessage = nil

        if FeatureFlags.csharpInviteEnabled {
            if await cancelInviteViaREST(id: id, fallback: "Couldn't cancel that invite.") {
                await load()
            }
            return
        }

        let response = await client.cancelBudgetInvite(request: .with {
            $0.id = id
            $0.budgetProfileID = budgetProfileID
        })

        switch response.result {
        case .success:
            await load()
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't cancel that invite."
        }
    }

    /// Cancels the still-pending invite first (if any) to avoid duplicate
    /// pending rows for the same address, then sends a fresh one with the
    /// same email/role/person — matches web's `handleResend`.
    func resend(_ invite: Wellspent_V1_BudgetInvite) async {
        errorMessage = nil

        if FeatureFlags.csharpInviteEnabled {
            if invite.status == .pending {
                guard await cancelInviteViaREST(id: invite.id, fallback: "Couldn't resend that invite.") else { return }
            }
            guard await sendInviteViaREST(email: invite.email, role: invite.role, budgetPersonID: invite.budgetPersonID, fallback: "Couldn't resend that invite.") != nil else { return }
            await load()
            return
        }

        if invite.status == .pending {
            let cancelResponse = await client.cancelBudgetInvite(request: .with {
                $0.id = invite.id
                $0.budgetProfileID = budgetProfileID
            })
            if case .failure(let error) = cancelResponse.result {
                errorMessage = error.message ?? "Couldn't resend that invite."
                return
            }
        }

        let response = await client.sendBudgetInvite(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.email = invite.email
            $0.role = invite.role
            $0.budgetPersonID = invite.budgetPersonID
        })

        switch response.result {
        case .success:
            await load()
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't resend that invite."
        }
    }
}
