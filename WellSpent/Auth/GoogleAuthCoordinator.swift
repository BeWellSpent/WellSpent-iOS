import AuthenticationServices
import Observation
import os
import UIKit
import WellSpentAPI

/// Drives native Google Sign-In via `ASWebAuthenticationSession`. Mirrors
/// web's `LoginForm.tsx`/`auth/callback/page.tsx` flow (random `state`,
/// `getGoogleAuthURL` → redirect to Google → `exchangeGoogleCode`), adapted
/// to a native presentation instead of a full-page navigation.
///
/// Reuses the exact same server-configured redirect
/// (`https://bewellspent.com/auth/callback`) web already uses, rather than a
/// custom URL scheme — confirmed against `auth_handler.go`/`oauth.go` that
/// the backend currently ignores any client-supplied `redirect_uri` on both
/// Google RPCs and always resolves to that URL server-side. A custom scheme
/// would also mean a second, dedicated Google Cloud "iOS" OAuth client
/// (different client ID, no secret, PKCE) — real external setup, and Google
/// now explicitly discourages custom-scheme redirects as an impersonation
/// risk.
///
/// **History, two failed attempts before this one** (see
/// `docs/features/google-auth.md`'s iOS section, workspace root, for the
/// full account): first tried `callbackURLScheme: nil` relying on
/// `ASWebAuthenticationSession`'s own completion handler to catch a
/// Universal Link — doesn't work, confirmed live. Then tried routing the
/// redirect through `RootView`'s `onOpenURL` instead — also doesn't work,
/// confirmed live, root cause found afterward: **Universal Links only
/// activate on a user-tapped link, never on an automatic server-side
/// redirect** (verified against Apple's own documented behavior), and
/// Google's OAuth callback is always the latter. Both attempts were
/// fundamentally unable to work, not implementation bugs.
///
/// The actual fix: `ASWebAuthenticationSession.Callback.https(host:path:)`
/// (iOS 17.4+, this app's deployment target was bumped from 17.0 to 17.4 for
/// this) — a *session-scoped* HTTPS callback that doesn't go through the
/// system Universal Links pipeline at all, so it isn't subject to the
/// user-tap restriction. This is the API Apple added specifically to solve
/// this exact "native app, third-party auth server, automatic redirect"
/// problem. Confirmed via a standalone `swiftc -typecheck` run that this
/// initializer requires iOS 17.4+ (fails to compile at 17.0, succeeds at
/// 17.4) before committing to the deployment target bump.
///
/// Language/currency are left empty on the exchange call — same as this
/// app's own `RegisterViewModel` for manual sign-up, which also leaves them
/// unset and lets the backend default to en/USD, rather than introducing a
/// new locale-tracking mechanism just for this flow.
@MainActor
@Observable
final class GoogleAuthCoordinator: NSObject {
    private static let redirectURI = "https://bewellspent.com/auth/callback"
    /// `print()` only reaches stdout, which is only captured when a debugger
    /// is attached — invisible from Console.app for a standalone-launched
    /// (TestFlight/Home-screen) process. `os.Logger` persists to the unified
    /// logging system instead, so it's visible in Console.app regardless of
    /// how the app was launched. Filter Console.app by subsystem
    /// `com.bewellspent.WellSpent` / category `GoogleAuth`, or just search
    /// "GoogleAuth". TODO: remove once the sign-in flow is confirmed working.
    private static let logger = Logger(subsystem: "com.bewellspent.WellSpent", category: "GoogleAuth")

    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_AuthServiceClient
    /// Held so it isn't deallocated mid-flow — `ASWebAuthenticationSession`
    /// doesn't retain itself.
    private var activeSession: ASWebAuthenticationSession?

    init(publicClient: ProtocolClient) {
        self.client = Wellspent_V1_AuthServiceClient(client: publicClient)
    }

    func signIn(session sessionStore: SessionStore) async {
        Self.logger.debug("signIn() called, isSigningIn=\(self.isSigningIn, privacy: .public)")
        guard !isSigningIn else {
            Self.logger.debug("already signing in, ignoring tap")
            return
        }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        let state = UUID().uuidString
        Self.logger.debug("requesting auth URL, state=\(state, privacy: .public)")
        let urlResponse = await client.getGoogleAuthURL(request: .with { $0.state = state })

        guard case .success(let urlMessage) = urlResponse.result else {
            if case .failure(let error) = urlResponse.result {
                Self.logger.error("getGoogleAuthURL FAILED: \(String(describing: error), privacy: .public)")
                errorMessage = error.message ?? "Couldn't start Google sign-in."
            }
            return
        }
        Self.logger.debug("got auth URL: \(urlMessage.url, privacy: .public)")
        guard let authURL = URL(string: urlMessage.url) else {
            Self.logger.error("auth URL string failed to parse as URL")
            errorMessage = "Couldn't start Google sign-in."
            return
        }

        let callbackURL: URL
        do {
            callbackURL = try await authenticate(url: authURL)
            Self.logger.debug("authenticate() returned callback URL: \(callbackURL.absoluteString, privacy: .public)")
        } catch let authError as ASWebAuthenticationSessionError where authError.code == .canceledLogin {
            Self.logger.debug("user cancelled")
            // User dismissed the sheet — not worth surfacing as an error.
            return
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost {
            Self.logger.error("session.start() returned false — webcredentials/associated domain misconfigured")
            errorMessage = "Couldn't start Google sign-in — check the app's associated domain configuration."
            return
        } catch {
            Self.logger.error("authenticate() threw: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }

        let code: String
        switch Self.extractCode(from: callbackURL, expectedState: state) {
        case .success(let extracted):
            code = extracted
        case .failure(let message):
            errorMessage = message
            return
        }

        let exchangeResponse = await client.exchangeGoogleCode(request: .with {
            $0.code = code
            $0.state = state
            $0.redirectUri = Self.redirectURI
        })

        switch exchangeResponse.result {
        case .success(let message):
            sessionStore.startSession(token: message.accessToken)
        case .failure(let error):
            errorMessage = error.message ?? "Google sign-in failed."
        }
    }

    /// Not `Result<String, String>` — `Result`'s `Failure` generic parameter
    /// requires `Error` conformance, which a plain `String` doesn't have.
    enum CodeExtraction: Equatable {
        case success(String)
        case failure(String)
    }

    /// Pure so it's independently testable without a live callback URL —
    /// mirrors web's callback page's own two checks (missing code, mismatched
    /// state), same order and same user-facing messages.
    nonisolated static func extractCode(from callbackURL: URL, expectedState: String) -> CodeExtraction {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return .failure("No authorization code received from Google.")
        }
        guard components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
            return .failure("Invalid state parameter. Please try again.")
        }
        return .success(code)
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: "bewellspent.com", path: "/auth/callback")
            ) { callbackURL, error in
                Self.logger.debug("session completion handler fired — callbackURL: \(String(describing: callbackURL), privacy: .public), error: \(String(describing: error), privacy: .public)")
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
            session.presentationContextProvider = self
            activeSession = session
            // `start()` returns `false` — with no error and no completion
            // handler call — when the association is misconfigured (e.g. the
            // `webcredentials:` associated-domain entitlement or the AASA
            // file's `webcredentials` section is missing/stale/not yet
            // propagated through Apple's CDN). Without this check, that
            // failure mode hangs the continuation forever: the button just
            // looks unresponsive with no way to tell why.
            let started = session.start()
            Self.logger.debug("session.start() returned \(started, privacy: .public)")
            guard started else {
                continuation.resume(throwing: URLError(.cannotConnectToHost))
                return
            }
        }
    }
}

extension GoogleAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
