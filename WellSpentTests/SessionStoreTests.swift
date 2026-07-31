import Foundation
import Testing
@testable import WellSpent

@Suite("SessionStore")
@MainActor
struct SessionStoreTests {
    private func makeTokenStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.bewellspent.WellSpent.tests.session.\(UUID().uuidString)")
    }

    @Test("starts logged out when the Keychain has no token")
    func startsLoggedOutWithNoToken() {
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore())
        #expect(!session.isAuthenticated)
        #expect(session.userID == nil)
        #expect(session.authenticatedClient == nil)
    }

    @Test("restores an authenticated session from a valid, unexpired token already in the Keychain")
    func restoresValidSession() {
        let tokenStore = makeTokenStore()
        tokenStore.save(token: makeJWT(subject: "user-42", expiresAt: Date().addingTimeInterval(3600)))

        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore)

        #expect(session.isAuthenticated)
        #expect(session.userID == "user-42")
        #expect(session.authenticatedClient != nil)
    }

    @Test("discards an expired token found in the Keychain at launch")
    func discardsExpiredTokenAtLaunch() {
        let tokenStore = makeTokenStore()
        tokenStore.save(token: makeJWT(expiresAt: Date().addingTimeInterval(-60)))

        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore)

        #expect(!session.isAuthenticated)
        #expect(tokenStore.readToken() == nil) // stale token is cleaned up, not left behind
    }

    @Test("startSession saves the token and flips to authenticated")
    func startSessionAuthenticates() {
        let tokenStore = makeTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore)

        session.startSession(token: makeJWT(subject: "user-99", expiresAt: Date().addingTimeInterval(3600)))

        #expect(session.isAuthenticated)
        #expect(session.userID == "user-99")
        #expect(tokenStore.readToken() != nil)
    }

    @Test("endSession clears the token, user, and authenticated client")
    func endSessionClearsState() {
        let tokenStore = makeTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore)
        session.startSession(token: makeJWT(expiresAt: Date().addingTimeInterval(3600)))

        session.endSession()

        #expect(!session.isAuthenticated)
        #expect(session.userID == nil)
        #expect(session.authenticatedClient == nil)
        #expect(tokenStore.readToken() == nil)
    }

    @Test("refreshAuthenticationState is a no-op while logged out")
    func refreshIsNoOpWhenLoggedOut() {
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore())
        session.refreshAuthenticationState()
        #expect(!session.isAuthenticated)
    }

    @Test("refreshAuthenticationState logs out when the stored token has since expired")
    func refreshLogsOutOnExpiry() {
        let tokenStore = makeTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore)
        session.startSession(token: makeJWT(expiresAt: Date().addingTimeInterval(3600)))

        // Simulate time passing / the token expiring while backgrounded by
        // overwriting the Keychain entry with an already-expired token.
        tokenStore.save(token: makeJWT(expiresAt: Date().addingTimeInterval(-1)))

        session.refreshAuthenticationState()

        #expect(!session.isAuthenticated)
    }

    @Test("refreshAuthenticationState keeps the session when the token is still valid")
    func refreshKeepsValidSession() {
        let tokenStore = makeTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore)
        session.startSession(token: makeJWT(subject: "user-7", expiresAt: Date().addingTimeInterval(3600)))

        session.refreshAuthenticationState()

        #expect(session.isAuthenticated)
        #expect(session.userID == "user-7")
    }
}
