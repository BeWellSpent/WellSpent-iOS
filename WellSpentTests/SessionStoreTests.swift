import Foundation
import Testing
@testable import WellSpent

/// Simulates the Keychain-gated refresh-token store without ever touching
/// the real Security framework — reading the real store triggers a system
/// Face ID/Touch ID prompt a unit test can't answer. `failRead` simulates a
/// declined prompt or a locked device even while `exists()` is true.
private final class FakeRefreshTokenStore: RefreshTokenStoring, @unchecked Sendable {
    var stored: String?
    var failRead = false
    private(set) var readCount = 0
    /// Which flag set the most recent `save` was asked for, and how many
    /// times `save` has been called — lets a test assert both the mapping
    /// and that a re-key actually happened (clear + save), without touching
    /// real Keychain/LocalAuthentication APIs.
    private(set) var lastAccessControl: RefreshTokenAccessControl?
    private(set) var saveCount = 0

    init(initial: String? = nil) { stored = initial }

    func exists() -> Bool { stored != nil }
    func read() async -> RefreshTokenReadResult {
        readCount += 1
        if failRead { return .unavailable }
        return stored.map(RefreshTokenReadResult.token) ?? .notFound
    }
    func save(token: String, accessControl: RefreshTokenAccessControl) {
        stored = token
        lastAccessControl = accessControl
        saveCount += 1
    }
    func clear() { stored = nil }
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
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

    private func makeBiometricDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.bewellspent.WellSpent.tests.session.biometric.\(UUID().uuidString)")!
    }

    /// Polls until `isResolvingSession` settles, so tests don't race the
    /// `Task` `init` kicks off for a cold-start resume.
    private func waitForResolution(_ session: SessionStore) async {
        for _ in 0..<200 where session.isResolvingSession {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test("starts logged out once resolved, when no refresh token exists")
    func startsLoggedOutWithNoRefreshToken() async {
        // isResolvingSession is briefly true even with nothing stored now.
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: FakeRefreshTokenStore(), deviceIDStore: makeDeviceIDStore())
        await waitForResolution(session)
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
            refreshCallOverride: { _, _ in .success(accessToken: makeJWT(subject: "user-7", expiresAt: Date().addingTimeInterval(900)), refreshToken: "rotated-refresh") }
        )
        await waitForResolution(session)

        #expect(!session.isResolvingSession)
        #expect(session.isAuthenticated)
        #expect(session.userID == "user-7")
        #expect(session.authenticatedRESTClient != nil)
        #expect(refreshStore.stored == "rotated-refresh") // rotation persisted
    }

    @Test("a declined or failed biometric read keeps the stored token and waits for a retry instead of logging out")
    func coldStartKeepsTokenWhenReadIsUnavailable() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        refreshStore.failRead = true
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in .rejected }
        )
        await waitForResolution(session)

        #expect(!session.isResolvingSession)
        #expect(!session.isAuthenticated)
        #expect(session.isAwaitingUnlock)
        #expect(refreshStore.exists()) // a failed read must never delete the session
    }

    @Test("retrying after a failed read resumes the session once the read works")
    func retryAfterUnavailableReadResumes() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        refreshStore.failRead = true
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in .success(accessToken: makeJWT(subject: "user-9", expiresAt: Date().addingTimeInterval(900)), refreshToken: "rotated") }
        )
        await waitForResolution(session)
        refreshStore.failRead = false

        session.retryResume()
        await waitForResolution(session)

        #expect(session.isAuthenticated)
        #expect(!session.isAwaitingUnlock)
        #expect(session.userID == "user-9")
    }

    @Test("an item that is simply not there falls back to logged out, not to the unlock screen")
    func coldStartWithMissingItemIsLoggedOut() async {
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: FakeRefreshTokenStore(), deviceIDStore: makeDeviceIDStore())
        await waitForResolution(session)

        #expect(!session.isAuthenticated)
        #expect(!session.isAwaitingUnlock)
    }

    @Test("cold-start resume fails when the server rejects the refresh token: falls back to logged out")
    func coldStartResumeFailsOnServerRejection() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in .rejected }
        )
        await waitForResolution(session)

        #expect(!session.isResolvingSession)
        #expect(!session.isAuthenticated)
        #expect(!session.isAwaitingUnlock)
        #expect(!refreshStore.exists())
    }

    @Test("a refresh that can't reach the server keeps the token and retries without reading the Keychain again")
    func coldStartTransientFailureKeepsSessionAndRetriesWithoutRereading() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        let online = Box(false)
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore(),
            refreshCallOverride: { _, _ in
                online.value
                    ? .success(accessToken: makeJWT(subject: "user-3", expiresAt: Date().addingTimeInterval(900)), refreshToken: "rotated")
                    : .unavailable
            }
        )
        await waitForResolution(session)
        #expect(session.isAwaitingUnlock)
        #expect(refreshStore.exists())

        online.value = true
        session.retryResume()
        await waitForResolution(session)

        #expect(session.isAuthenticated)
        #expect(refreshStore.readCount == 1) // one Face ID prompt, not two
    }

    @Test("abandoning the resume clears the stored session and shows the login screen")
    func abandonResumeLogsOut() async {
        let refreshStore = FakeRefreshTokenStore(initial: "stored-refresh")
        refreshStore.failRead = true
        let session = SessionStore(
            baseURL: "http://localhost:1",
            tokenStore: makeTokenStore(),
            refreshTokenStore: refreshStore,
            deviceIDStore: makeDeviceIDStore()
        )
        await waitForResolution(session)

        session.abandonResume()

        #expect(!session.isAwaitingUnlock)
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

    @Test("startSession writes the refresh token under userPresence when the biometric-only preference is off")
    func startSessionUsesUserPresenceByDefault() {
        let refreshStore = FakeRefreshTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: refreshStore, deviceIDStore: makeDeviceIDStore(), biometricPreferenceDefaults: makeBiometricDefaults())

        session.startSession(accessToken: makeJWT(subject: "user-1", expiresAt: Date().addingTimeInterval(900)), refreshToken: "a-refresh-token")

        #expect(refreshStore.lastAccessControl == .userPresence)
    }

    @Test("startSession writes the refresh token under biometryCurrentSet when the biometric-only preference is on")
    func startSessionUsesBiometryCurrentSetWhenPreferenceOn() {
        let refreshStore = FakeRefreshTokenStore()
        let biometricDefaults = makeBiometricDefaults()
        BiometricPreference.setEnabled(true, in: biometricDefaults)
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: refreshStore, deviceIDStore: makeDeviceIDStore(), biometricPreferenceDefaults: biometricDefaults)

        session.startSession(accessToken: makeJWT(subject: "user-2", expiresAt: Date().addingTimeInterval(900)), refreshToken: "a-refresh-token")

        #expect(refreshStore.lastAccessControl == .biometryCurrentSet)
    }

    @Test("applyBiometricPreferenceChange re-keys the stored refresh token immediately when a session is active")
    func applyBiometricPreferenceChangeRekeysActiveSession() {
        let refreshStore = FakeRefreshTokenStore()
        let biometricDefaults = makeBiometricDefaults()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: refreshStore, deviceIDStore: makeDeviceIDStore(), biometricPreferenceDefaults: biometricDefaults)
        session.startSession(accessToken: makeJWT(subject: "user-3", expiresAt: Date().addingTimeInterval(900)), refreshToken: "a-refresh-token")
        #expect(refreshStore.lastAccessControl == .userPresence)
        let saveCountAfterStart = refreshStore.saveCount

        BiometricPreference.setEnabled(true, in: biometricDefaults)
        session.applyBiometricPreferenceChange()

        #expect(refreshStore.saveCount == saveCountAfterStart + 1)
        #expect(refreshStore.lastAccessControl == .biometryCurrentSet)
        #expect(refreshStore.stored == "a-refresh-token") // same token, re-keyed not replaced
    }

    @Test("applyBiometricPreferenceChange is a no-op when no session is active")
    func applyBiometricPreferenceChangeNoSessionIsNoOp() {
        let refreshStore = FakeRefreshTokenStore()
        let session = SessionStore(baseURL: "http://localhost:1", tokenStore: makeTokenStore(), refreshTokenStore: refreshStore, deviceIDStore: makeDeviceIDStore(), biometricPreferenceDefaults: makeBiometricDefaults())

        session.applyBiometricPreferenceChange()

        #expect(refreshStore.saveCount == 0)
    }
}
