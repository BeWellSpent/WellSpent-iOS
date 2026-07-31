import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class RegisterViewModel {
    var email = ""
    var password = ""
    var firstName = ""
    var lastName = ""
    var countryCode = ""
    var stateCode = ""

    private(set) var countries: [Wellspent_V1_Country] = []
    private(set) var isSubmitting = false
    private(set) var isLoadingCountries = false
    private(set) var errorMessage: String?
    private(set) var didRegister = false

    private let authClient: Wellspent_V1_AuthServiceClient
    private let userClient: Wellspent_V1_UserServiceClient

    var isUnitedStates: Bool { countryCode == "US" }

    var canSubmit: Bool {
        LoginViewModel.isValidEmail(email)
            && RegisterViewModel.passwordError(for: password) == nil
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSubmitting
    }

    init(publicClient: ProtocolClient) {
        self.authClient = Wellspent_V1_AuthServiceClient(client: publicClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: publicClient)
    }

    func loadCountries() async {
        guard countries.isEmpty else { return }
        isLoadingCountries = true
        defer { isLoadingCountries = false }

        let response = await userClient.listCountries(request: Wellspent_V1_ListCountriesRequest())
        if let message = response.message {
            countries = message.countries.filter(\.isEnabled)
        }
    }

    func submit(session: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_RegisterRequest.with {
            $0.email = email
            $0.password = password
            $0.firstName = firstName
            $0.lastName = lastName
            $0.countryCode = countryCode
            $0.stateCode = isUnitedStates ? stateCode : ""
        }
        let response = await authClient.register(request: request)

        switch response.result {
        case .success(let message):
            session.startSession(token: message.accessToken)
            didRegister = true
        case .failure(let error):
            errorMessage = RegisterViewModel.errorMessage(for: error)
        }
    }

    /// Mirrors the backend's `validatePassword` exactly (see
    /// `WellSpent-backend/internal/service/auth_service.go`): ≥8 characters,
    /// at least one uppercase, lowercase, digit, and punctuation/symbol
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

    static func errorMessage(for error: ConnectError) -> String {
        switch error.code {
        case .alreadyExists:
            return "An account with that email already exists."
        case .invalidArgument:
            return error.message ?? "Please check your details and try again."
        case .unavailable, .deadlineExceeded:
            return "Can't reach the server. Check your connection and try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
