import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class AcceptInviteViewModel {
    private(set) var invite: Wellspent_V1_BudgetInvite?
    private(set) var isLoading = false
    private(set) var isAccepting = false
    private(set) var errorMessage: String?
    private(set) var acceptedBudgetProfileID: String?

    let token: String

    private let publicClient: Wellspent_V1_InviteServiceClient
    /// `nil` when the invite link was opened before the user is
    /// authenticated — `load()` (the public preview) still works either way;
    /// `accept()` requires this to be set.
    private let authenticatedClient: Wellspent_V1_InviteServiceClient?

    init(token: String, publicClient: ProtocolClient, authenticatedClient: ProtocolClient?) {
        self.token = token
        self.publicClient = Wellspent_V1_InviteServiceClient(client: publicClient)
        self.authenticatedClient = authenticatedClient.map { Wellspent_V1_InviteServiceClient(client: $0) }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response = await publicClient.getBudgetInvite(request: .with { $0.token = token })
        switch response.result {
        case .success(let message):
            invite = message.invite
        case .failure(let error):
            errorMessage = Self.loadErrorMessage(for: error)
        }
    }

    /// A dead link has to read like an explanation, not a stack trace.
    ///
    /// `notFound` is the ordinary case rather than an exceptional one: an
    /// invite is deleted when its budget is (`budget_invite` cascades from
    /// `budget_profile`), so cancelling a half-built budget kills every link
    /// already emailed from it. The server's own message for that is
    /// `invite "<uuid>" not found`, which reads as a defect and puts a raw
    /// token on screen. Every other failure keeps the server's wording, which
    /// is written for the reader — "this invitation has expired", "…has
    /// already been accepted".
    ///
    /// Web does the same, mapping `Code.NotFound` to `invite.error.notFound`
    /// in `InviteAcceptContent.tsx`.
    static func loadErrorMessage(for error: ConnectError) -> String {
        let locale = AppLanguageStore.currentLocale
        let bundle = AppLanguageStore.currentBundle
        switch error.code {
        case .notFound:
            return String(localized: "This invitation is no longer available. Ask whoever invited you to send a new one.",
                          bundle: bundle, locale: locale)
        case .unavailable, .deadlineExceeded:
            return String(localized: "Can't reach the server. Check your connection and try again.",
                          bundle: bundle, locale: locale)
        default:
            return error.message ?? String(localized: "That invite link isn't valid.",
                                           bundle: bundle, locale: locale)
        }
    }

    func accept() async {
        // Defensive only — the UI replaces this action with Sign In/Register
        // buttons whenever `authenticatedClient` is nil, so this guard
        // shouldn't be reachable in practice.
        guard let authenticatedClient else { return }

        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }

        let response = await authenticatedClient.acceptBudgetInvite(request: .with { $0.token = token })
        switch response.result {
        case .success(let message):
            acceptedBudgetProfileID = message.budgetProfileID
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't accept that invite."
        }
    }
}
