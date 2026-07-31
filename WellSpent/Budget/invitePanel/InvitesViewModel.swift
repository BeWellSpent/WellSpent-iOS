import Foundation
import Observation
import WellSpentAPI

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

    /// Mirrors web's `useBudgetRole`: the profile owner is always Admin;
    /// otherwise resolved from the matching linked `BudgetPerson`'s role.
    var isAdmin: Bool {
        guard let currentUserID, !currentUserID.isEmpty else { return false }
        if currentUserID == budgetOwnerUserID { return true }
        return people.first(where: { !$0.userID.isEmpty && $0.userID == currentUserID })?.role == .admin
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

    init(budgetProfileID: String, budgetOwnerUserID: String, currentUserID: String?, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.budgetOwnerUserID = budgetOwnerUserID
        self.currentUserID = currentUserID
        self.client = Wellspent_V1_InviteServiceClient(client: authenticatedClient)
        self.budgetClient = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
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

        async let invitesResponse = client.listBudgetInvites(request: .with { $0.budgetProfileID = budgetProfileID })
        async let peopleResponse = budgetClient.listBudgetPeople(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await invitesResponse.result {
        case .success(let message):
            invites = message.invites
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load invites."
        }

        if case .success(let message) = await peopleResponse.result {
            people = message.people
        }
    }

    func send() async {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

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

    func cancel(id: String) async {
        errorMessage = nil
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
