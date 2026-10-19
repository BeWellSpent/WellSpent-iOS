import Foundation
import Observation
import WellSpentREST

/// App-wide auth state. Owns the Keychain-backed token and builds the REST
/// clients other screens use: `publicRESTClient` for pre-login calls
/// (Register/Login/GetBudgetInvite, ...) and `authenticatedRESTClient`,
/// rebuilt on login/logout, for everything else.
///
/// Deliberately does **not** call a refresh-token RPC proactively — the web
/// app has one available too but never calls it; on expiry it just logs out.
@MainActor
@Observable
final class SessionStore {
    private(set) var isAuthenticated: Bool
    private(set) var userID: String?

    let publicRESTClient: WellSpentREST.Client
    private(set) var authenticatedRESTClient: WellSpentREST.Client?

    private let tokenStore: KeychainTokenStore
    private let baseURL: String

    init(baseURL: String = APIEnvironment.baseURL, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.publicRESTClient = RESTClient.makePublicClient(baseURL: baseURL)

        if let token = tokenStore.readToken(), let claims = JWT.decode(token), !claims.isExpired {
            isAuthenticated = true
            userID = claims.subject
        } else {
            tokenStore.deleteToken()
            isAuthenticated = false
            userID = nil
        }
        authenticatedRESTClient = nil
        if isAuthenticated {
            authenticatedRESTClient = Self.makeAuthenticatedRESTClient(baseURL: baseURL, tokenStore: tokenStore) { [weak self] in
                self?.endSession()
            }
        }
    }

    /// Called on a successful Login/Register response.
    func startSession(token: String) {
        tokenStore.save(token: token)
        userID = JWT.decode(token)?.subject
        isAuthenticated = true
        authenticatedRESTClient = Self.makeAuthenticatedRESTClient(baseURL: baseURL, tokenStore: tokenStore) { [weak self] in
            self?.endSession()
        }
    }

    func endSession() {
        tokenStore.deleteToken()
        authenticatedRESTClient = nil
        isAuthenticated = false
        userID = nil
        AppLanguageStore.clear()
    }

    /// Call when the app becomes active — the Swift equivalent of the web
    /// app's `visibilitychange` check: if the stored token has since expired
    /// while the app was backgrounded, log out rather than leave the user on
    /// a stale authenticated screen that will just 401 on the next request.
    func refreshAuthenticationState() {
        guard isAuthenticated else { return }
        guard let token = tokenStore.readToken(), let claims = JWT.decode(token), !claims.isExpired else {
            endSession()
            return
        }
    }

    private static func makeAuthenticatedRESTClient(
        baseURL: String,
        tokenStore: KeychainTokenStore,
        onUnauthenticated: @escaping @Sendable @MainActor () -> Void
    ) -> WellSpentREST.Client {
        RESTClient.makeAuthenticatedClient(
            baseURL: baseURL,
            tokenProvider: { tokenStore.readToken() },
            onUnauthenticated: {
                Task { @MainActor in
                    onUnauthenticated()
                }
            }
        )
    }
}
