import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

/// App-wide auth state. Owns the Keychain-backed token and builds the
/// ConnectRPC clients other screens use. Direct analog of the web app's
/// `AuthContext` + `TransportProvider`: `publicClient` mirrors
/// `publicTransport` (Register/Login/GetBudgetInvite), `authenticatedClient`
/// mirrors `createTransport(token)`.
///
/// The `*RESTClient` pair is the same split for the REST transport — the
/// endpoints that are global and cacheable rather than Connect. Public and
/// authenticated are kept separate there for a reason beyond symmetry:
/// attaching a token to a public endpoint makes the response look
/// user-specific to a cache that cannot know otherwise.
///
/// Deliberately does **not** call `AuthService.RefreshToken` proactively —
/// the web app has that RPC available too but never calls it; on expiry it
/// just logs out. Matched here for parity, not because refresh isn't useful.
@MainActor
@Observable
final class SessionStore {
    private(set) var isAuthenticated: Bool
    private(set) var userID: String?
    private(set) var authenticatedClient: ProtocolClient?

    let publicClient: ProtocolClient
    let publicRESTClient: WellSpentREST.Client
    private(set) var authenticatedRESTClient: WellSpentREST.Client?

    private let tokenStore: KeychainTokenStore
    private let baseURL: String

    init(baseURL: String = APIEnvironment.baseURL, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.publicClient = APIClient.makePublicClient(baseURL: baseURL)
        self.publicRESTClient = RESTClient.makePublicClient(baseURL: baseURL)

        if let token = tokenStore.readToken(), let claims = JWT.decode(token), !claims.isExpired {
            isAuthenticated = true
            userID = claims.subject
        } else {
            tokenStore.deleteToken()
            isAuthenticated = false
            userID = nil
        }
        authenticatedClient = nil
        authenticatedRESTClient = nil
        if isAuthenticated {
            authenticatedClient = Self.makeAuthenticatedClient(baseURL: baseURL, tokenStore: tokenStore) { [weak self] in
                self?.endSession()
            }
            authenticatedRESTClient = Self.makeAuthenticatedRESTClient(baseURL: baseURL, tokenStore: tokenStore)
        }
    }

    /// Called on a successful Login/Register response.
    func startSession(token: String) {
        tokenStore.save(token: token)
        userID = JWT.decode(token)?.subject
        isAuthenticated = true
        authenticatedClient = Self.makeAuthenticatedClient(baseURL: baseURL, tokenStore: tokenStore) { [weak self] in
            self?.endSession()
        }
        authenticatedRESTClient = Self.makeAuthenticatedRESTClient(baseURL: baseURL, tokenStore: tokenStore)
    }

    func endSession() {
        tokenStore.deleteToken()
        authenticatedClient = nil
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

    /// No `onUnauthenticated` counterpart: the one authenticated REST endpoint
    /// is the changelog, and a 401 there surfaces as an ordinary thrown error
    /// the caller already handles. Tearing the session down from a screen the
    /// reader opened to look at release notes would be a worse outcome than
    /// showing nothing — the Connect client covers the real session expiry.
    private static func makeAuthenticatedRESTClient(
        baseURL: String,
        tokenStore: KeychainTokenStore
    ) -> WellSpentREST.Client {
        RESTClient.makeAuthenticatedClient(
            baseURL: baseURL,
            tokenProvider: { tokenStore.readToken() }
        )
    }

    private static func makeAuthenticatedClient(
        baseURL: String,
        tokenStore: KeychainTokenStore,
        onUnauthenticated: @escaping @MainActor () -> Void
    ) -> ProtocolClient {
        APIClient.makeAuthenticatedClient(
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
