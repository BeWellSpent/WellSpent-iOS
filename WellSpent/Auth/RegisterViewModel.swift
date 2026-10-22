import Foundation
import Observation
import WellSpentREST

@MainActor
@Observable
final class RegisterViewModel {
    var email = ""
    var password = ""
    var firstName = ""
    var lastName = ""
    var countryCode = ""
    var stateCode = ""

    private(set) var countries: [Country] = []
    private(set) var isSubmitting = false
    private(set) var isLoadingCountries = false
    private(set) var errorMessage: String?
    private(set) var didRegister = false

    /// The country list lives on the REST transport, where it is cacheable —
    /// it is the same three rows for every caller on earth and changes roughly
    /// never. Deliberately the *public* REST client even here, on an
    /// authenticated screen: sending a token would make the response look
    /// user-specific to a cache that cannot know otherwise.
    private let restClient: WellSpentREST.Client

    var isUnitedStates: Bool { countryCode == "US" }

    var canSubmit: Bool {
        LoginViewModel.isValidEmail(email)
            && RegisterViewModel.passwordError(for: password) == nil
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSubmitting
    }

    init(publicRESTClient: WellSpentREST.Client) {
        self.restClient = publicRESTClient
    }

    func loadCountries() async {
        guard countries.isEmpty else { return }
        isLoadingCountries = true
        defer { isLoadingCountries = false }

        if let fetched = try? await restClient.enabledCountries() {
            countries = fetched.filter(\.isEnabled)
        }
    }

    /// Empty language/currency/captchaToken — required-present but let the backend default; no Turnstile on iOS.
    func submit(session: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let output = try await session.publicRESTClient.registerUser(.init(body: .json(.init(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                countryCode: countryCode,
                stateCode: isUnitedStates ? stateCode : "",
                language: "",
                currency: "",
                captchaToken: "",
                deviceId: session.deviceID
            ))))
            switch output {
            case .ok(let ok):
                let body = try ok.body.json
                session.startSession(accessToken: body.accessToken, refreshToken: body.refreshToken)
                didRegister = true
            case .conflict:
                errorMessage = "An account with that email already exists."
            case .badRequest(let badRequest):
                errorMessage = (try? badRequest.body.json.message) ?? "Please check your details and try again."
            default:
                errorMessage = "Something went wrong. Please try again."
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Something went wrong. Please try again."
        }
    }

    /// Mirrors the backend's password validation exactly: ≥8 characters, at
    /// least one uppercase, lowercase, digit, and punctuation/symbol
    /// character. Returns a user-facing message, or `nil` if valid.
    static func passwordError(for password: String) -> String? {
        guard password.count >= 8 else {
            return "Password must be at least 8 characters."
        }
        var hasUpper = false, hasLower = false, hasDigit = false, hasSpecial = false
        for character in password {
            if character.isUppercase { hasUpper = true }
            if character.isLowercase { hasLower = true }
            if character.isNumber { hasDigit = true }
            if character.isPunctuation || character.isSymbol { hasSpecial = true }
        }
        guard hasUpper, hasLower, hasDigit, hasSpecial else {
            return "Password must contain an uppercase letter, lowercase letter, digit, and special character."
        }
        return nil
    }
}
