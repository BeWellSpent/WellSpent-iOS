import Foundation
import Observation
import os
import WellSpentREST

/// App-wide auth state. Owns the Keychain-backed tokens and builds the REST
/// clients other screens use: `publicRESTClient` for pre-login calls
/// (Register/Login/RefreshToken/...) and `authenticatedRESTClient`, rebuilt on
/// login/logout, for everything else.
///
/// The access token (15 min) refreshes reactively on a 401, rotating the
/// Keychain-gated refresh token too. Concurrent 401s share one in-flight
/// refresh. `init` resumes a session asynchronously, tracked via
/// `isResolvingSession` so `RootView` can wait instead of flashing the login
/// screen. The stored session is deleted only when it is genuinely gone or the
/// server refuses it; a failed unlock or a network error sets
/// `isAwaitingUnlock` so the user can retry.
/// What the `/auth/refresh-token` call came back with, before it is applied.
enum RefreshCallResult: Sendable {
    case success(accessToken: String, refreshToken: String)
    case rejected
    case unavailable
}

@MainActor
@Observable
final class SessionStore {
    private(set) var isAuthenticated: Bool
    private(set) var isResolvingSession: Bool
    /// The session is intact but could not be resumed this time (Face ID
    /// declined/failed, device locked, or no connection).
    private(set) var isAwaitingUnlock = false
    private(set) var userID: String?

    let publicRESTClient: WellSpentREST.Client
    /// Signs register and login requests with this install's App Attest key (#121).
    @ObservationIgnored let appAttest: AppAttestClient
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
    private let refreshCallOverride: (@Sendable (String, String) async -> RefreshCallResult)?

    /// Kept in memory for the life of the foreground session so a reactive
    /// 401 refresh never needs to re-read (and re-prompt for) the Keychain.
    private var refreshToken: String?

    private static let logger = AppLogger.logger("SessionStore")
    private let instanceID = UUID().uuidString.prefix(8)

    /// Scopes every auth call this store makes to one stable device.
    var deviceID: String { deviceIDStore.deviceID() }

    init(
        baseURL: String = APIEnvironment.baseURL,
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        refreshTokenStore: any RefreshTokenStoring = KeychainRefreshTokenStore(),
        deviceIDStore: AuthDeviceIDStore = AuthDeviceIDStore(),
        biometricPreferenceDefaults: UserDefaults = .standard,
        refreshCallOverride: (@Sendable (String, String) async -> RefreshCallResult)? = nil
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.refreshTokenStore = refreshTokenStore
        self.deviceIDStore = deviceIDStore
        self.biometricPreferenceDefaults = biometricPreferenceDefaults
        self.refreshCallOverride = refreshCallOverride
        self.publicRESTClient = RESTClient.makePublicClient(baseURL: baseURL)
        self.appAttest = AppAttestClient(restClient: publicRESTClient)

        isAuthenticated = false
        userID = nil
        authenticatedRESTClient = nil

        Self.logger.info("SessionStore.init called id=\(self.instanceID, privacy: .public)")

        // No separate exists() pre-check — read()'s own result already
        // distinguishes "nothing stored" from "declined", both handled by
        // resumeSession()'s clearLocalSession() path.
        isResolvingSession = true
        Task { @MainActor [weak self] in
            await self?.resumeSession()
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
            refreshAccessToken: { [weak self] in await self?.refreshAccessTokenInSession() ?? .unavailable },
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
    /// Only a missing item or a server rejection ends the session; a failed
    /// unlock or an unreachable server parks it on the unlock screen.
    private func resumeSession() async {
        defer { isResolvingSession = false }
        Self.logger.info("resumeSession() entered id=\(self.instanceID, privacy: .public)")
        isAwaitingUnlock = false

        let storedRefreshToken: String
        if let refreshToken {
            storedRefreshToken = refreshToken // already unlocked; a retry must not prompt again
        } else {
            switch await refreshTokenStore.read() {
            case .token(let token):
                storedRefreshToken = token
            case .notFound:
                Self.logger.info("cold-start resume: no stored refresh token")
                clearLocalSession()
                return
            case .unavailable:
                Self.logger.error("cold-start resume: refresh token unreadable (prompt declined/failed or device locked) — keeping it, awaiting retry")
                isAwaitingUnlock = true
                return
            }
        }

        switch await performRefresh(refreshToken: storedRefreshToken) {
        case .refreshed(let accessToken):
            userID = JWT.decode(accessToken)?.subject
            isAuthenticated = true
            authenticatedRESTClient = Self.makeAuthenticatedRESTClient(
                baseURL: baseURL,
                tokenStore: tokenStore,
                refreshAccessToken: { [weak self] in await self?.refreshAccessTokenInSession() ?? .unavailable },
                onUnauthenticated: { [weak self] in self?.endSession() }
            )
            Self.logger.info("cold-start resume succeeded")
        case .rejected:
            Self.logger.error("cold-start resume: server rejected the refresh token")
            clearLocalSession()
        case .unavailable:
            Self.logger.error("cold-start resume: refresh call could not complete — keeping the session, awaiting retry")
            refreshToken = storedRefreshToken
            isAwaitingUnlock = true
        }
    }

    /// The unlock screen's "Try again".
    func retryResume() {
        guard isAwaitingUnlock, !isResolvingSession else { return }
        isResolvingSession = true
        Task { @MainActor [weak self] in
            await self?.resumeSession()
        }
    }

    /// The unlock screen's "Log in with password instead".
    func abandonResume() {
        endSession()
    }

    /// Shares one in-flight refresh across concurrent 401s — the backend
    /// rotates the refresh token per use and treats reuse as theft, so
    /// racing calls must not each refresh independently.
    private var inFlightRefresh: Task<TokenRefreshOutcome, Never>?

    /// In-session refresh triggered by a 401 from any authenticated call.
    private func refreshAccessTokenInSession() async -> TokenRefreshOutcome {
        if let inFlightRefresh {
            return await inFlightRefresh.value
        }
        guard let refreshToken else {
            Self.logger.error("in-session refresh attempted with no refresh token in memory")
            return .rejected
        }
        let task = Task { await self.performRefresh(refreshToken: refreshToken) }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }

    /// Shared by both refresh paths: exchanges a refresh token, persists and
    /// returns the new access token on success. Only the server saying 401
    /// counts as `.rejected`; a thrown error or any other status is `.unavailable`.
    private func performRefresh(refreshToken: String) async -> TokenRefreshOutcome {
        let result: RefreshCallResult
        if let refreshCallOverride {
            result = await refreshCallOverride(refreshToken, deviceID)
        } else {
            result = await callRefreshEndpoint(refreshToken: refreshToken)
        }
        switch result {
        case .success(let accessToken, let newRefreshToken):
            persist(accessToken: accessToken, refreshToken: newRefreshToken)
            return .refreshed(accessToken)
        case .rejected:
            return .rejected
        case .unavailable:
            return .unavailable
        }
    }

    private func callRefreshEndpoint(refreshToken: String) async -> RefreshCallResult {
        do {
            let output = try await publicRESTClient.refreshToken(.init(body: .json(.init(
                refreshToken: refreshToken,
                deviceId: deviceID
            ))))
            switch output {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(accessToken: body.accessToken, refreshToken: body.refreshToken)
            case .unauthorized:
                Self.logger.error("refresh-token call rejected deviceId=\(self.deviceID, privacy: .public)")
                return .rejected
            default:
                Self.logger.error("refresh-token call failed deviceId=\(self.deviceID, privacy: .public) output=\(String(describing: output), privacy: .public)")
                return .unavailable
            }
        } catch {
            let result = Self.refreshResult(forThrown: error)
            Self.logger.error("refresh-token call failed deviceId=\(self.deviceID, privacy: .public) result=\(String(describing: result), privacy: .public) error=\(String(describing: error), privacy: .public)")
            return result
        }
    }

    /// The server's error body doesn't decode against the contract (it sends
    /// `Code`/`Message`, the contract says `code`/`message`), so a refusal
    /// arrives as a thrown decoding error carrying the 401 rather than as
    /// `.unauthorized`. Without this a revoked token would look like an outage.
    static func refreshResult(forThrown error: Error) -> RefreshCallResult {
        isUnauthorizedResponse(error) ? .rejected : .unavailable
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
        isAwaitingUnlock = false
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
        refreshAccessToken: @escaping @Sendable @MainActor () async -> TokenRefreshOutcome,
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
