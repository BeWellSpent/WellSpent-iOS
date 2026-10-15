import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

/// Backs both Plaid screens.
///
/// Settings lists the caller's connections across every budget; a budget's
/// manage view lists every member's connections on one budget. Only the query
/// scope and the row captions differ — the Link session handling and all five
/// mutations are identical, so they live here once rather than in two view
/// models that would drift apart.
@MainActor
@Observable
final class PlaidConnectionsViewModel {
    /// A fresh connect exchanges the returned public token for a new item.
    /// An update-mode session (account selection on an existing item)
    /// doesn't return a usable public token — Link still calls onSuccess,
    /// but the right follow-up is to re-sync the connection's account list,
    /// not exchange. Mirrors web's `LinkSession` discriminated union in
    /// `PlaidSection.tsx` exactly, for the same reason: one Link callback
    /// serving two different follow-up RPCs.
    enum LinkSession {
        case connect(budgetProfileID: String)
        case update(connectionID: String)
    }

    /// Must be a Plaid-dashboard-registered redirect URI (confirmed against
    /// LinkKit's own CHANGELOG — current versions handle the OAuth
    /// continuation internally via `ASWebAuthenticationSession`, no custom
    /// `onOpenURL` routing needed here, but the token still won't redirect
    /// back to Link without this being set correctly at creation time).
    /// Verified via the Universal Link path added to `bewellspent.com`'s
    /// `apple-app-site-association` file alongside this feature.
    static let redirectURI = "https://bewellspent.com/plaid-oauth-redirect"

    private(set) var isLoading = false
    private(set) var connections: [Wellspent_V1_PlaidConnection] = []
    /// Connections on shared budgets that the sync job skips. Not a subset of
    /// `connections` — those are the caller's own; these belong to co-members
    /// and are never otherwise visible here.
    private(set) var syncWarnings: [Wellspent_V1_BudgetSyncWarning] = []
    private(set) var budgets: [Wellspent_V1_BudgetProfile] = []
    private(set) var errorMessage: String?

    private(set) var activeLinkSession: LinkSession?
    private(set) var activeLinkToken: String?
    private(set) var managingAccountsConnectionID: String?
    private(set) var disconnectingConnectionID: String?
    private(set) var resyncingConnectionID: String?

    private let plaidClient: Wellspent_V1_PlaidServiceClient
    private let budgetClient: Wellspent_V1_BudgetServiceClient
    private let userClient: Wellspent_V1_UserServiceClient
    private let restClient: WellSpentREST.Client

    /// The caller's plan. Supplied by Settings, which has already fetched it;
    /// resolved here for the budget screen, which hasn't — the same
    /// fetch-your-own-plan convention `AlertsViewModel` and `PeopleViewModel`
    /// already follow rather than plumbing it through the budget shell.
    private(set) var plan: Wellspent_V1_AccountPlan
    var isFree: Bool { plan == .unspecified || plan == .free }

    /// Non-nil scopes the list to one budget, returning every member's
    /// connections rather than only the caller's.
    let budgetProfileID: String?

    private static let logger = AppLogger.logger("Plaid")

    init(authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client, budgetProfileID: String? = nil, plan: Wellspent_V1_AccountPlan? = nil) {
        self.plaidClient = Wellspent_V1_PlaidServiceClient(client: authenticatedClient)
        self.budgetClient = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = restClient
        self.budgetProfileID = budgetProfileID
        self.plan = plan ?? .unspecified
        self.needsPlanFetch = plan == nil
    }

    private let needsPlanFetch: Bool

    /// Not private, so plan-dependent gating is testable without a live
    /// `GetMe` call.
    func setStateForTesting(plan: Wellspent_V1_AccountPlan) {
        self.plan = plan
    }

    /// Warnings for the budget in scope only. The response covers every budget
    /// the caller belongs to, and another budget's problem isn't actionable
    /// from a budget-scoped screen.
    var visibleWarnings: [Wellspent_V1_BudgetSyncWarning] {
        guard let budgetProfileID else { return syncWarnings }
        return syncWarnings.filter { $0.budgetProfileID == budgetProfileID }
    }

    /// The caption under each row: which budget it feeds when listing across
    /// budgets, or who linked it when listing one budget's.
    func subtitle(for connection: Wellspent_V1_PlaidConnection) -> String {
        if budgetProfileID == nil {
            return budgetName(for: connection.budgetProfileID)
        }
        return connection.ownerName.isEmpty
            ? String(localized: "Unknown member", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
            : connection.ownerName
    }

    /// Not private, so `budgetName(for:)` is testable without a live
    /// `ListBudgetProfiles` call.
    func setStateForTesting(budgets: [Wellspent_V1_BudgetProfile]) {
        self.budgets = budgets
    }

    /// Not private, so warning filtering is testable without a live
    /// `GetPlaidConnections` call.
    func setStateForTesting(warnings: [Wellspent_V1_BudgetSyncWarning]) {
        self.syncWarnings = warnings
    }

    func budgetName(for budgetProfileID: String) -> String {
        budgets.first(where: { $0.id == budgetProfileID })?.name ?? "Unknown budget"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let connectionsResult = fetchConnections()
        // Only the cross-budget list needs these — for row captions and the
        // connect-flow budget picker. A budget-scoped screen already knows
        // which budget it's on and captions rows by owner instead.
        async let budgetsResponse = budgetProfileID == nil
            ? budgetClient.listBudgetProfiles(request: Wellspent_V1_ListBudgetProfilesRequest())
            : nil

        if let fetched = await connectionsResult {
            connections = fetched.connections
            syncWarnings = fetched.warnings
        }

        if case .success(let message)? = await budgetsResponse?.result {
            budgets = message.profiles
        }

        if needsPlanFetch, let user = await UserRESTMapping.currentUser(connectClient: userClient, restClient: restClient, useREST: FeatureFlags.csharpUserEnabled) {
            plan = user.plan
        }
    }

    private func fetchConnections() async -> (connections: [Wellspent_V1_PlaidConnection], warnings: [Wellspent_V1_BudgetSyncWarning])? {
        if FeatureFlags.csharpPlaidEnabled {
            do {
                let output = try await restClient.getPlaidConnections(.init(query: .init(budgetProfileId: budgetProfileID)))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = "Couldn't load connected bank accounts."
                    return nil
                }
                return (body.connections.map(PlaidRESTMapping.connection(from:)), body.warnings.map(PlaidRESTMapping.syncWarning(from:)))
            } catch {
                // A cancelled request isn't a real failure — see the Connect path's identical note below.
                if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load connected bank accounts."
                return nil
            }
        }

        let response = await plaidClient.getPlaidConnections(request: .with {
            if let budgetProfileID { $0.budgetProfileID = budgetProfileID }
        })
        switch response.result {
        case .success(let message):
            return (message.connections, message.warnings)
        case .failure(let error):
            // A cancelled request isn't a real failure — SwiftUI can cancel
            // this view's `.task` mid-flight (e.g. during a navigation
            // transition) and restart it; surfacing that as a "cancelled"
            // error message to the user is just noise from a request that
            // never got to finish, not something the user did wrong.
            if error.code != .canceled {
                errorMessage = error.message ?? "Couldn't load connected bank accounts."
            }
            return nil
        }
    }

    func startConnect(budgetProfileID: String) async {
        errorMessage = nil

        if FeatureFlags.csharpPlaidEnabled {
            guard let linkToken = await createLinkTokenViaREST(budgetProfileID: budgetProfileID, connectionID: nil, fallback: "Couldn't start bank connection.") else { return }
            activeLinkSession = .connect(budgetProfileID: budgetProfileID)
            activeLinkToken = linkToken
            return
        }

        let response = await plaidClient.createLinkToken(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.redirectUri = Self.redirectURI
        })

        switch response.result {
        case .success(let message):
            activeLinkSession = .connect(budgetProfileID: budgetProfileID)
            activeLinkToken = message.linkToken
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't start bank connection."
        }
    }

    func startManageAccounts(_ connection: Wellspent_V1_PlaidConnection) async {
        errorMessage = nil
        managingAccountsConnectionID = connection.id

        if FeatureFlags.csharpPlaidEnabled {
            guard let linkToken = await createLinkTokenViaREST(budgetProfileID: connection.budgetProfileID, connectionID: connection.id, fallback: "Couldn't start account management.") else {
                managingAccountsConnectionID = nil
                return
            }
            activeLinkSession = .update(connectionID: connection.id)
            activeLinkToken = linkToken
            return
        }

        let response = await plaidClient.createLinkToken(request: .with {
            $0.budgetProfileID = connection.budgetProfileID
            $0.connectionID = connection.id
            $0.redirectUri = Self.redirectURI
        })

        switch response.result {
        case .success(let message):
            activeLinkSession = .update(connectionID: connection.id)
            activeLinkToken = message.linkToken
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't start account management."
            managingAccountsConnectionID = nil
        }
    }

    private func createLinkTokenViaREST(budgetProfileID: String, connectionID: String?, fallback: String) async -> String? {
        do {
            let output = try await restClient.createLinkToken(.init(body: .json(.init(
                budgetProfileId: budgetProfileID,
                connectionId: connectionID,
                redirectUri: Self.redirectURI
            ))))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = fallback
                return nil
            }
            return body.linkToken
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return nil
        }
    }

    func handleLinkSuccess(publicToken: String) async {
        let session = activeLinkSession
        activeLinkSession = nil
        activeLinkToken = nil
        defer { managingAccountsConnectionID = nil }

        guard let session else { return }
        errorMessage = nil

        if FeatureFlags.csharpPlaidEnabled {
            switch session {
            case .connect(let budgetProfileID):
                do {
                    guard case .ok = try await restClient.exchangePublicToken(.init(body: .json(.init(publicToken: publicToken, budgetProfileId: budgetProfileID)))) else {
                        errorMessage = "Couldn't finish connecting that bank."
                        return
                    }
                } catch {
                    errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't finish connecting that bank."
                }
            case .update(let connectionID):
                do {
                    guard case .ok = try await restClient.refreshPlaidAccounts(.init(path: .init(id: connectionID))) else {
                        errorMessage = "Couldn't refresh that connection's accounts."
                        return
                    }
                } catch {
                    errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't refresh that connection's accounts."
                }
            }
            await load()
            return
        }

        switch session {
        case .connect(let budgetProfileID):
            let response = await plaidClient.exchangePublicToken(request: .with {
                $0.publicToken = publicToken
                $0.budgetProfileID = budgetProfileID
            })
            if case .failure(let error) = response.result {
                errorMessage = error.message ?? "Couldn't finish connecting that bank."
            }
        case .update(let connectionID):
            let response = await plaidClient.refreshPlaidAccounts(request: .with { $0.connectionID = connectionID })
            if case .failure(let error) = response.result {
                errorMessage = error.message ?? "Couldn't refresh that connection's accounts."
            }
        }

        await load()
    }

    func handleLinkExit() {
        activeLinkSession = nil
        activeLinkToken = nil
        managingAccountsConnectionID = nil
    }

    /// Clears the connection's cursor so the next sync replays its full
    /// history, and starts that sync server-side straight away.
    func resync(_ connection: Wellspent_V1_PlaidConnection) async {
        errorMessage = nil
        resyncingConnectionID = connection.id
        defer { resyncingConnectionID = nil }

        if FeatureFlags.csharpPlaidEnabled {
            let fallback = String(localized: "Couldn't re-sync that bank.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
            do {
                let output = try await restClient.resyncPlaidConnection(.init(path: .init(id: connection.id)))
                switch output {
                case .ok:
                    Self.logger.info("plaid resync started id=\(connection.id, privacy: .public)")
                    await load()
                case .badRequest(let badRequest):
                    errorMessage = (try? badRequest.body.json.message) ?? fallback
                default:
                    errorMessage = fallback
                }
            } catch {
                Self.logger.error("plaid resync REST failed id=\(connection.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            }
            return
        }

        let response = await plaidClient.resyncPlaidConnection(request: .with { $0.connectionID = connection.id })
        switch response.result {
        case .success:
            Self.logger.info("plaid resync started id=\(connection.id, privacy: .public)")
            await load()
        case .failure(let error):
            Self.logger.error("plaid resync failed id=\(connection.id, privacy: .public) code=\(String(describing: error.code), privacy: .public)")
            errorMessage = error.message ?? String(localized: "Couldn't re-sync that bank.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
    }

    func disconnect(_ connection: Wellspent_V1_PlaidConnection) async {
        errorMessage = nil
        disconnectingConnectionID = connection.id
        defer { disconnectingConnectionID = nil }

        if FeatureFlags.csharpPlaidEnabled {
            do {
                guard case .ok = try await restClient.disconnectPlaid(.init(path: .init(id: connection.id))) else {
                    errorMessage = "Couldn't disconnect that bank."
                    return
                }
                await load()
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't disconnect that bank."
            }
            return
        }

        let response = await plaidClient.disconnectPlaid(request: .with { $0.connectionID = connection.id })
        switch response.result {
        case .success:
            await load()
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't disconnect that bank."
        }
    }
}
