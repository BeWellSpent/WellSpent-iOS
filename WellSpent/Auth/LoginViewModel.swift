import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    var rememberMe = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_AuthServiceClient

    var canSubmit: Bool {
        LoginViewModel.isValidEmail(email) && !password.isEmpty && !isSubmitting
    }

    init(publicClient: ProtocolClient) {
        self.client = Wellspent_V1_AuthServiceClient(client: publicClient)
    }

    func submit(session: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_LoginRequest.with {
            $0.email = email
            $0.password = password
            $0.rememberMe = rememberMe
        }
        let response = await client.login(request: request)

        switch response.result {
        case .success(let message):
            session.startSession(token: message.accessToken)
        case .failure(let error):
            errorMessage = LoginViewModel.errorMessage(for: error)
        }
    }

    /// Simple, permissive email-shape check — the backend is the real
    /// authority on validity. This just avoids submitting obviously-broken
    /// input and enables/disables the submit button.
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Maps backend error codes (see `WellSpent-backend/internal/handler/errors.go`)
    /// to user-facing copy. `.invalidArgument` covers both "wrong email/password"
    /// and validation failures — the backend intentionally returns the same
    /// generic message for both on login to avoid leaking which part was wrong.
    static func errorMessage(for error: ConnectError) -> String {
        switch error.code {
        case .invalidArgument:
            return "Incorrect email or password."
        case .permissionDenied:
            return error.message ?? "This account can't sign in right now."
        case .unavailable, .deadlineExceeded:
            return "Can't reach the server. Check your connection and try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
