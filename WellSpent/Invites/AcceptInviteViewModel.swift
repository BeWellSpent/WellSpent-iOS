import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AcceptInviteViewModel {
    private(set) var invite: Wellspent_V1_BudgetInvite?
    private(set) var isLoading = false
    private(set) var isAccepting = false
    private(set) var errorMessage: String?
    private(set) var acceptedBudgetProfileID: String?

    let token: String

    private let publicRESTClient: WellSpentREST.Client
    /// `nil` when the invite link was opened before the user is
    /// authenticated — `load()` (the public preview) still works either way;
    /// `accept()` requires this to be set.
    private let authenticatedRESTClient: WellSpentREST.Client?

    init(
        token: String,
        publicRESTClient: WellSpentREST.Client,
        authenticatedRESTClient: WellSpentREST.Client?
    ) {
        self.token = token
        self.publicRESTClient = publicRESTClient
        self.authenticatedRESTClient = authenticatedRESTClient
    }

    /// A truly nonexistent token comes back **404**, which the OpenAPI
    /// contract doesn't document (confirmed live), so it lands in
    /// `.undocumented` rather than a named case.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let locale = AppLanguageStore.currentLocale
        let bundle = AppLanguageStore.currentBundle
        let notFoundMessage = String(localized: "This invitation is no longer available. Ask whoever invited you to send a new one.", bundle: bundle, locale: locale)
        let genericMessage = String(localized: "That invite link isn't valid.", bundle: bundle, locale: locale)
        do {
            let output = try await publicRESTClient.getBudgetInvite(.init(path: .init(token: token)))
            switch output {
            case .ok(let ok):
                guard let body = try? ok.body.json else { errorMessage = genericMessage; return }
                invite = InviteRESTMapping.invite(from: body.invite)
            case .badRequest(let badRequest):
                errorMessage = (try? badRequest.body.json.message) ?? genericMessage
            case .undocumented(let statusCode, _):
                errorMessage = statusCode == 404 ? notFoundMessage : genericMessage
            default:
                errorMessage = genericMessage
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? genericMessage
        }
    }

    func accept() async {
        // Defensive only — the UI replaces this action with Sign In/Register
        // buttons whenever `authenticatedRESTClient` is nil, so this guard
        // shouldn't be reachable in practice.
        guard let authenticatedRESTClient else { return }
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }

        do {
            let output = try await authenticatedRESTClient.acceptBudgetInvite(.init(path: .init(token: token)))
            switch output {
            case .ok(let ok):
                acceptedBudgetProfileID = try? ok.body.json.budgetProfileId
            case .badRequest(let badRequest):
                errorMessage = (try? badRequest.body.json.message) ?? "Couldn't accept that invite."
            default:
                errorMessage = "Couldn't accept that invite."
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't accept that invite."
        }
    }
}
