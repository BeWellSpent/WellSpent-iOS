import AuthenticationServices
import Foundation
import Observation
import os
import WellSpentAPI

/// Drives native Sign in with Apple.
///
/// Far simpler than `GoogleAuthCoordinator`: `ASAuthorizationAppleIDProvider`
/// hands back a signed identity token directly, so there is no browser sheet,
/// no `state` round trip, no redirect URI, and none of the Universal Link
/// machinery that took four attempts to get right for Google. The button
/// itself (`SignInWithAppleButton`) owns the request/response plumbing; this
/// type only turns the resulting credential into a session.
@MainActor
@Observable
final class AppleAuthCoordinator {
    private static let logger = AppLogger.logger("AppleAuth")

    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_AuthServiceClient

    init(publicClient: ProtocolClient) {
        self.client = Wellspent_V1_AuthServiceClient(client: publicClient)
    }

    /// Handles the result handed over by `SignInWithAppleButton`'s
    /// `onCompletion`.
    func handle(result: Result<ASAuthorization, Error>, session: SessionStore) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                Self.logger.error("authorization returned an unexpected credential type")
                errorMessage = Self.genericErrorMessage()
                return
            }
            await signIn(credential: credential, session: session)

        case .failure(let error):
            // A cancelled sheet is a normal outcome, not something to nag
            // about — same treatment GoogleAuthCoordinator gives its own
            // cancellation case.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            Self.logger.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = Self.genericErrorMessage()
        }
    }

    func signIn(credential: ASAuthorizationAppleIDCredential, session: SessionStore) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        guard let identityToken = Self.string(from: credential.identityToken) else {
            Self.logger.error("credential carried no identity token")
            errorMessage = Self.genericErrorMessage()
            return
        }
        // Apple returns the name only on the very first authorization and
        // never again, so it has to be forwarded now or it's lost — the
        // backend stores it at account-creation time and never overwrites it.
        let name = Self.nameComponents(from: credential.fullName)

        let response = await client.signInWithApple(request: .with {
            $0.identityToken = identityToken
            $0.authorizationCode = Self.string(from: credential.authorizationCode) ?? ""
            $0.firstName = name.first
            $0.lastName = name.last
        })

        switch response.result {
        case .success(let message):
            session.startSession(token: message.accessToken)
        case .failure(let error):
            Self.logger.error("signInWithApple RPC failed code=\(String(describing: error.code), privacy: .public)")
            errorMessage = Self.errorMessage(for: error)
        }
    }

    // MARK: - Pure helpers

    /// Splits Apple's `PersonNameComponents` into the two flat fields the RPC
    /// carries. Both are empty for a returning user, since Apple only ever
    /// populates the name once.
    nonisolated static func nameComponents(from components: PersonNameComponents?) -> (first: String, last: String) {
        guard let components else { return ("", "") }
        return (components.givenName ?? "", components.familyName ?? "")
    }

    nonisolated static func string(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let value = String(decoding: data, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    /// Maps backend error codes (see `WellSpent-backend/internal/handler/errors.go`)
    /// to user-facing copy, mirroring `LoginViewModel.errorMessage(for:)`.
    ///
    /// Unlike `GoogleAuthCoordinator` — whose messages are plain literals and
    /// therefore ship English-only regardless of the user's chosen language —
    /// these go through `String(localized:locale:)` with an explicit locale,
    /// which is required outside a SwiftUI view body.
    nonisolated static func errorMessage(for error: ConnectError) -> String {
        switch error.code {
        case .invalidArgument:
            return String(
                localized: "Apple sign-in couldn't be verified. Please try again.",
                locale: AppLanguageStore.currentLocale
            )
        case .permissionDenied:
            return String(
                localized: "This account can't sign in right now.",
                locale: AppLanguageStore.currentLocale
            )
        case .unavailable, .deadlineExceeded:
            return String(
                localized: "Can't reach the server. Check your connection and try again.",
                locale: AppLanguageStore.currentLocale
            )
        default:
            return genericErrorMessage()
        }
    }

    nonisolated static func genericErrorMessage() -> String {
        String(localized: "Apple sign-in failed. Please try again.", locale: AppLanguageStore.currentLocale)
    }
}
