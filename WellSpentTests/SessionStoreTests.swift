import Foundation
import Testing
@testable import WellSpent

/// Simulates the Keychain-gated refresh-token store without ever touching
/// the real Security framework — reading the real store triggers a system
/// Face ID/Touch ID prompt a unit test can't answer. `failRead` simulates a
/// declined prompt or an undecryptable item even while `exists()` is true.
private final class FakeRefreshTokenStore: RefreshTokenStoring, @unchecked Sendable {
    var stored: String?
    var failRead = false

    init(initial: String? = nil) { stored = initial }

    func exists() -> Bool { stored != nil }
    func read() async -> String? { failRead ? nil : stored }
    func save(token: String) { stored = token }
    func clear() { stored = nil }
}

@Suite("SessionStore")
@MainActor
struct SessionStoreTests {
    private func makeTokenStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.bewellspent.WellSpent.tests.session.\(UUID().uuidString)")
    }

    private func makeDeviceIDStore() -> AuthDeviceIDStore {
        AuthDeviceIDStore(service: "com.bewellspent.WellSpent.tests.session.deviceID.\(UUID().uuidString)")
    }

    /// Polls until `isResolvingSession` settles, so tests don't race the
    /// `Task` `init` kicks off for a cold-start resume.
    private func waitForResolution(_ session: SessionStore) async {
        for _ in 0..<200 where session.isResolvingSession {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test("starts logged out, already resolved, when no refresh token exists")
    func startsLoggedOutWithNoRefreshToken() async {
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: FakeRefreshTokenStore(), deviceIDStore: makeDeviceIDStore())
        #expect(!session.isResolvingSession)
        #expect(!session.isAuthenticated)
        #expect(session.userID == nil)
        #expect(session.authenticatedRESTClient == nil)
    }

    @Test("cold-start resume succeeds: exchanges the stored refresh token and authenticates")
    func coldStartResumeSucceeds() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in (accessToken: makeJWT(subject: "user-7", expiresAt: Date().addingTimeInterval(900)), refreshToken: "rotated-refresh") }
        )
        await waitForResolution(session)

        #expect(!session.isResolvingSession)
        #expect(session.isAuthenticated)
        #expect(session.userID == "user-7")
        #expect(session.authenticatedRESTClient != nil)
        #expect(refreshStore.stored == "rotated-refresh") // rotation persisted
    }

    @Test("cold-start resume fails when the biometric read is declined: falls back to logged out")
    func coldStartResumeFailsOnDeclinedRead() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        refreshStore.failRead = true
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in (accessToken: "unused", refreshToken: "unused") }
        )
        await waitForResolution(session)

        #expect(!session.isResolvingSession)
        #expect(!session.isAuthenticated)
        #expect(!refreshStore.exists()) // declined read clears the local item too
    }

    @Test("cold-start resume fails when the server rejects the refresh token: falls back to logged out")
    func coldStartResumeFailsOnServerRejection() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in nil }
        )
        await waitForResolution(session)

        #expect(!session.isResolvingSession)
        #expect(!session.isAuthenticated)
        #expect(!refreshStore.exists())
    }

    @Test("startSession persists both tokens and flips to authenticated")
    func startSessionAuthenticates() {
        let tokenStore = makeTokenStore()
        let refreshStore = FakeRefreshTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore, refreshTokenStore: refreshStore, deviceIDStore: makeDeviceIDStore())

        session.startSession(accessToken: makeJWT(subject: "user-99", expiresAt: Date().addingTimeInterval(900)), refreshToken: "a-refresh-token")

        #expect(session.isAuthenticated)
        #expect(session.userID == "user-99")
        #expect(tokenStore.readToken() != nil)
        #expect(refreshStore.stored == "a-refresh-token")
    }

    @Test("endSession clears both tokens, the user, and the authenticated client")
    func endSessionClearsState() {
        let tokenStore = makeTokenStore()
        let refreshStore = FakeRefreshTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: tokenStore, refreshTokenStore: refreshStore, deviceIDStore: makeDeviceIDStore())
        session.startSession(accessToken: makeJWT(expiresAt: Date().addingTimeInterval(900)), refreshToken: "a-refresh-token")

        session.endSession()

        #expect(!session.isAuthenticated)
        #expect(session.userID == nil)
        #expect(session.authenticatedRESTClient == nil)
        #expect(tokenStore.readToken() == nil)
        #expect(!refreshStore.exists())
    }
}
