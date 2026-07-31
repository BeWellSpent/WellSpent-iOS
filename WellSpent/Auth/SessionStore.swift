import Foundation
import Observation
import WellSpentAPI

/// App-wide auth state. Owns the Keychain-backed token and builds the
/// ConnectRPC clients other screens use. Direct analog of the web app's
/// `AuthContext` + `TransportProvider`: `publicClient` mirrors
/// `publicTransport` (Register/Login/ListCountries), `authenticatedClient`
/// mirrors `createTransport(token)`.
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

    private let tokenStore: KeychainTokenStore
    private let baseURL: String

    init(baseURL: String = APIEnvironment.baseURL, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.publicClient = APIClient.makePublicClient(baseURL: baseURL)

        if let token = tokenStore.readToken(), let claims = JWT.decode(token), !claims.isExpired {
            isAuthenticated = true
            userID = claims.subject
        } else {
            tokenStore.deleteToken()
            isAuthenticated = false
            userID = nil
        }
        authenticatedClient = nil
        if isAuthenticated {
            authenticatedClient = Self.makeAuthenticatedClient(baseURL: baseURL, tokenStore: tokenStore) { [weak self] in
                self?.endSession()
            }
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
    }

    func endSession() {
        tokenStore.deleteToken()
        authenticatedClient = nil
        isAuthenticated = false
        userID = nil
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
