import AuthenticationServices
import Observation
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
/// risk. Instead this relies on the app's existing `applinks:bewellspent.com`
/// associated domain (already used for invite links and Plaid's OAuth
/// continuation, see `PlaidSectionViewModel.redirectURI`'s doc comment).
/// Requires `/auth/callback` to be listed in `WellSpent-web`'s
/// `apple-app-site-association` file (added alongside this).
///
/// **`ASWebAuthenticationSession`'s own completion handler does not reliably
/// fire for Universal Link redirects** — this is a known, long-standing gap
/// (confirmed against multiple Apple Developer Forum threads, not specific
/// to this app): when the OS intercepts a Universal Link, it delivers it to
/// the app's normal `onOpenURL` handler, not to the session's completion
/// handler, which is left showing the real loaded page with no way to know
/// the app already got what it needed. So the actual callback is routed
/// through `RootView`'s existing `onOpenURL` (the same mechanism that
/// already handles invite links) via `pendingCallback`, a static
/// closure-router — mirrors `AppDelegate.onDeviceToken`'s existing pattern
/// for the same "external event, whichever object currently cares" shape.
/// The session's own completion handler is kept only as a fallback (and to
/// detect user-initiated cancellation) — whichever source resolves first
/// wins, guarded by `resumeOnce`.
///
/// Language/currency are left empty on the exchange call — same as this
/// app's own `RegisterViewModel` for manual sign-up, which also leaves them
/// unset and lets the backend default to en/USD, rather than introducing a
/// new locale-tracking mechanism just for this flow.
@MainActor
@Observable
final class GoogleAuthCoordinator: NSObject {
    private static let redirectURI = "https://bewellspent.com/auth/callback"

    /// Set while a sign-in is in flight; cleared once resolved. `RootView`'s
    /// `onOpenURL` calls this when it sees `/auth/callback`.
    static var pendingCallback: ((URL) -> Void)?

    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_AuthServiceClient
    /// Held so it isn't deallocated mid-flow, and so it can be explicitly
    /// dismissed once `onOpenURL` delivers the callback instead of
    /// `ASWebAuthenticationSession`'s own completion handler.
    private var activeSession: ASWebAuthenticationSession?

    init(publicClient: ProtocolClient) {
        self.client = Wellspent_V1_AuthServiceClient(client: publicClient)
    }

    func signIn(session sessionStore: SessionStore) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        let state = UUID().uuidString
        let urlResponse = await client.getGoogleAuthURL(request: .with { $0.state = state })

        guard case .success(let urlMessage) = urlResponse.result else {
            if case .failure(let error) = urlResponse.result {
                errorMessage = error.message ?? "Couldn't start Google sign-in."
            }
            return
        }
        guard let authURL = URL(string: urlMessage.url) else {
            errorMessage = "Couldn't start Google sign-in."
            return
        }

        let callbackURL: URL
        do {
            callbackURL = try await authenticate(url: authURL)
        } catch let authError as ASWebAuthenticationSessionError where authError.code == .canceledLogin {
            // User dismissed the sheet — not worth surfacing as an error.
            return
        } catch {
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
            var didResume = false
            let resumeOnce: (Result<URL, Error>) -> Void = { [weak self] result in
                guard !didResume else { return }
                didResume = true
                Self.pendingCallback = nil
                self?.activeSession?.cancel()
                switch result {
                case .success(let url): continuation.resume(returning: url)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            Self.pendingCallback = { callbackURL in
                resumeOnce(.success(callbackURL))
            }

            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { callbackURL, error in
                if let callbackURL {
                    resumeOnce(.success(callbackURL))
                } else {
                    resumeOnce(.failure(error ?? URLError(.badServerResponse)))
                }
            }
            session.presentationContextProvider = self
            activeSession = session
            session.start()
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
