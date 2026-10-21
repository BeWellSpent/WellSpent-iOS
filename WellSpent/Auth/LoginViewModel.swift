import Foundation
import Observation
import WellSpentREST

@MainActor
@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    var rememberMe = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    var canSubmit: Bool {
        LoginViewModel.isValidEmail(email) && !password.isEmpty && !isSubmitting
    }

    func submit(session: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let output = try await session.publicRESTClient.login(.init(body: .json(.init(
                email: email,
                password: password,
                rememberMe: rememberMe,
                deviceId: session.deviceID
            ))))
            switch output {
            case .ok(let ok):
                let body = try ok.body.json
                session.startSession(accessToken: body.accessToken, refreshToken: body.refreshToken)
            case .badRequest:
                errorMessage = "Incorrect email or password."
            case .forbidden(let forbidden):
                errorMessage = (try? forbidden.body.json.message) ?? "This account can't sign in right now."
            default:
                errorMessage = "Something went wrong. Please try again."
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Something went wrong. Please try again."
        }
    }

    /// Simple, permissive email-shape check — the backend is the real
    /// authority on validity. This just avoids submitting obviously-broken
    /// input and enables/disables the submit button.
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
