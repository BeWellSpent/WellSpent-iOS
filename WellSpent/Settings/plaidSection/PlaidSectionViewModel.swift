import Observation
import WellSpentAPI

@MainActor
@Observable
final class PlaidSectionViewModel {
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
    private(set) var budgets: [Wellspent_V1_BudgetProfile] = []
    private(set) var errorMessage: String?

    private(set) var activeLinkSession: LinkSession?
    private(set) var activeLinkToken: String?
    private(set) var managingAccountsConnectionID: String?
    private(set) var disconnectingConnectionID: String?

    private let plaidClient: Wellspent_V1_PlaidServiceClient
    private let budgetClient: Wellspent_V1_BudgetServiceClient

    init(authenticatedClient: ProtocolClient) {
        self.plaidClient = Wellspent_V1_PlaidServiceClient(client: authenticatedClient)
        self.budgetClient = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    /// Not private, so `budgetName(for:)` is testable without a live
    /// `ListBudgetProfiles` call.
    func setStateForTesting(budgets: [Wellspent_V1_BudgetProfile]) {
        self.budgets = budgets
    }

    func budgetName(for budgetProfileID: String) -> String {
        budgets.first(where: { $0.id == budgetProfileID })?.name ?? "Unknown budget"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let connectionsResponse = plaidClient.getPlaidConnections(request: Wellspent_V1_GetPlaidConnectionsRequest())
        async let budgetsResponse = budgetClient.listBudgetProfiles(request: Wellspent_V1_ListBudgetProfilesRequest())

        switch await connectionsResponse.result {
        case .success(let message):
            connections = message.connections
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load connected bank accounts."
        }

        if case .success(let message) = await budgetsResponse.result {
            budgets = message.profiles
        }
    }

    func startConnect(budgetProfileID: String) async {
        errorMessage = nil
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

    func handleLinkSuccess(publicToken: String) async {
        let session = activeLinkSession
        activeLinkSession = nil
        activeLinkToken = nil
        defer { managingAccountsConnectionID = nil }

        guard let session else { return }
        errorMessage = nil

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

    func disconnect(_ connection: Wellspent_V1_PlaidConnection) async {
        errorMessage = nil
        disconnectingConnectionID = connection.id
        defer { disconnectingConnectionID = nil }

        let response = await plaidClient.disconnectPlaid(request: .with { $0.connectionID = connection.id })
        switch response.result {
        case .success:
            await load()
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't disconnect that bank."
        }
    }
}
