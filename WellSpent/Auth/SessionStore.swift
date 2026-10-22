import Foundation
import Observation
import os
import WellSpentREST

/// App-wide auth state. Owns the Keychain-backed tokens and builds the REST
/// clients other screens use: `publicRESTClient` for pre-login calls
/// (Register/Login/RefreshToken/...) and `authenticatedRESTClient`, rebuilt on
/// login/logout, for everything else.
///
/// The access token is short-lived (15 minutes) and refreshed reactively on a
/// 401 using the in-memory refresh token — no Keychain read, no biometric
/// prompt, while the app is actively running. The refresh token itself lives
/// behind a Face ID/Touch ID (or passcode) gate that only fires once per
/// cold start: `init` resumes a session asynchronously if one might exist,
/// tracked via `isResolvingSession` so `RootView` can wait for it instead of
/// flashing the login screen.
@MainActor
@Observable
final class SessionStore {
    private(set) var isAuthenticated: Bool
    private(set) var isResolvingSession: Bool
    private(set) var userID: String?

    let publicRESTClient: WellSpentREST.Client
    private(set) var authenticatedRESTClient: WellSpentREST.Client?

    private let tokenStore: KeychainTokenStore
    private let refreshTokenStore: any RefreshTokenStoring
    private let deviceIDStore: AuthDeviceIDStore
    private let baseURL: String
    /// Where `BiometricPreference` is read from — injectable so tests don't
    /// share `UserDefaults.standard`'s global state with each other or the app.
    private let biometricPreferenceDefaults: UserDefaults

    /// Overrides the real `/auth/refresh-token` network call in tests, so the
    /// refresh paths are exercisable without hitting a live backend.
    private let refreshCallOverride: (@Sendable (String, String) async -> (accessToken: String, refreshToken: String)?)?

    /// Kept in memory for the life of the foreground session so a reactive
    /// 401 refresh never needs to re-read (and re-prompt for) the Keychain.
    private var refreshToken: String?

    private static let logger = AppLogger.logger("SessionStore")

    /// Scopes every auth call this store makes to one stable device.
    var deviceID: String { deviceIDStore.deviceID() }

    init(
        baseURL: String = APIEnvironment.baseURL,
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        refreshTokenStore: any RefreshTokenStoring = KeychainRefreshTokenStore(),
        deviceIDStore: AuthDeviceIDStore = AuthDeviceIDStore(),
        biometricPreferenceDefaults: UserDefaults = .standard,
        refreshCallOverride: (@Sendable (String, String) async -> (accessToken: String, refreshToken: String)?)? = nil
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.refreshTokenStore = refreshTokenStore
        self.deviceIDStore = deviceIDStore
        self.biometricPreferenceDefaults = biometricPreferenceDefaults
        self.refreshCallOverride = refreshCallOverride
        self.publicRESTClient = RESTClient.makePublicClient(baseURL: baseURL)

        isAuthenticated = false
        userID = nil
        authenticatedRESTClient = nil

        if refreshTokenStore.exists() {
            isResolvingSession = true
            Task { @MainActor [weak self] in
                await self?.resumeSession()
            }
        } else {
            isResolvingSession = false
            tokenStore.deleteToken()
        }
    }

    /// Called on a successful Login/Register/Google/Apple response.
    func startSession(accessToken: String, refreshToken: String) {
        persist(accessToken: accessToken, refreshToken: refreshToken)
        userID = JWT.decode(accessToken)?.subject
        isAuthenticated = true
        authenticatedRESTClient = Self.makeAuthenticatedRESTClient(
            baseURL: baseURL,
            tokenStore: tokenStore,
            refreshAccessToken: { [weak self] in await self?.refreshAccessTokenInSession() },
            onUnauthenticated: { [weak self] in self?.endSession() }
        )
    }

    /// Best-effort revokes the refresh token server-side, then clears local
    /// state unconditionally — a failed logout call must never block sign-out.
    func endSession() {
        let tokenToRevoke = refreshToken
        clearLocalSession()
        AppLanguageStore.clear()

        guard let tokenToRevoke else { return }
        let client = publicRESTClient
        let deviceID = deviceID
        Task.detached {
            do {
                _ = try await client.logout(.init(body: .json(.init(refreshToken: tokenToRevoke))))
            } catch {
                Self.logger.error("logout call failed deviceId=\(deviceID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Cold-start resume: reads the refresh token (the one point in a session
    /// this prompts for Face ID/Touch ID) and exchanges it for a fresh pair.
    /// Any failure — declined prompt, missing/undecryptable item, or a
    /// rejected refresh call — falls back to the login screen.
    private func resumeSession() async {
        defer { isResolvingSession = false }

        guard let storedRefreshToken = await refreshTokenStore.read() else {
            Self.logger.error("cold-start resume: refresh token unreadable (declined prompt or missing item)")
            clearLocalSession()
            return
        }
        guard let accessToken = await performRefresh(refreshToken: storedRefreshToken) else {
            Self.logger.error("cold-start resume: refresh-token exchange failed")
            clearLocalSession()
            return
        }

        userID = JWT.decode(accessToken)?.subject
        isAuthenticated = true
        authenticatedRESTClient = Self.makeAuthenticatedRESTClient(
            baseURL: baseURL,
            tokenStore: tokenStore,
            refreshAccessToken: { [weak self] in await self?.refreshAccessTokenInSession() },
            onUnauthenticated: { [weak self] in self?.endSession() }
        )
        Self.logger.info("cold-start resume succeeded")
    }

    /// In-session refresh triggered by a 401 from any authenticated call —
    /// uses the in-memory refresh token only, no Keychain read, no prompt.
    private func refreshAccessTokenInSession() async -> String? {
        guard let refreshToken else {
            Self.logger.error("in-session refresh attempted with no refresh token in memory")
            return nil
        }
        return await performRefresh(refreshToken: refreshToken)
    }

    /// Shared by both refresh paths: exchanges a refresh token, persists and
    /// returns the new access token on success.
    private func performRefresh(refreshToken: String) async -> String? {
        if let refreshCallOverride {
            guard let result = await refreshCallOverride(refreshToken, deviceID) else { return nil }
            persist(accessToken: result.accessToken, refreshToken: result.refreshToken)
            return result.accessToken
        }
        do {
            let output = try await publicRESTClient.refreshToken(.init(body: .json(.init(
                refreshToken: refreshToken,
                deviceId: deviceID
            ))))
            guard case .ok(let ok) = output else {
                Self.logger.error("refresh-token call rejected deviceId=\(self.deviceID, privacy: .public) output=\(String(describing: output), privacy: .public)")
                return nil
            }
            let body = try ok.body.json
            persist(accessToken: body.accessToken, refreshToken: body.refreshToken)
            return body.accessToken
        } catch {
            Self.logger.error("refresh-token call failed deviceId=\(self.deviceID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func persist(accessToken: String, refreshToken: String) {
        tokenStore.save(token: accessToken)
        refreshTokenStore.save(token: refreshToken, accessControl: BiometricPreference.accessControl(in: biometricPreferenceDefaults))
        self.refreshToken = refreshToken
    }

    /// Re-keys the already-stored refresh token under the current
    /// `BiometricPreference` right away, rather than waiting for the next
    /// natural rotation — called from Settings the moment the toggle changes,
    /// so the setting doesn't sit silently not-yet-in-effect. A no-op when no
    /// session is active, since there's nothing stored to re-key yet.
    func applyBiometricPreferenceChange() {
        guard let refreshToken else {
            Self.logger.info("biometric preference changed with no active session — nothing to re-key")
            return
        }
        let accessControl = BiometricPreference.accessControl(in: biometricPreferenceDefaults)
        refreshTokenStore.clear()
        refreshTokenStore.save(token: refreshToken, accessControl: accessControl)
        Self.logger.info("refresh token re-keyed accessControl=\(String(describing: accessControl), privacy: .public)")
    }

    private func clearLocalSession() {
        tokenStore.deleteToken()
        refreshTokenStore.clear()
        refreshToken = nil
        authenticatedRESTClient = nil
        isAuthenticated = false
        userID = nil
    }

    /// `refreshAccessToken`/`onUnauthenticated` are `@MainActor`-typed so the
    /// weak `self` capture at each call site is sound without `self` itself
    /// being `Sendable` — both are bridged into the plain `@Sendable`
    /// closures `RESTClient.makeAuthenticatedClient` actually takes.
    private static func makeAuthenticatedRESTClient(
        baseURL: String,
        tokenStore: KeychainTokenStore,
        refreshAccessToken: @escaping @Sendable @MainActor () async -> String?,
        onUnauthenticated: @escaping @Sendable @MainActor () -> Void
    ) -> WellSpentREST.Client {
        RESTClient.makeAuthenticatedClient(
            baseURL: baseURL,
            tokenProvider: { tokenStore.readToken() },
            refreshAccessToken: {
                await refreshAccessToken()
            },
            onUnauthenticated: {
                Task { @MainActor in
                    onUnauthenticated()
                }
            }
        )
    }
}
