import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class SettingsViewModel {
    var firstName = ""
    var lastName = ""
    var countryCode = ""
    var stateCode = ""
    var filingStatus: Wellspent_V1_FilingStatus = .unspecified
    var taxPaymentFrequency: Wellspent_V1_TaxPaymentFrequency = .unspecified
    var language = "en"
    var currency = "USD"

    var currentPassword = ""
    var newPassword = ""

    private(set) var email = ""
    /// True when `email` is an Apple "Hide My Email" relay alias. Decided by
    /// the backend, not by suffix-matching the relay domain here, so every
    /// client answers it the same way.
    ///
    /// Wraps the generated `hasApplePrivateEmail_p` — swift-protobuf appends
    /// `_p` to any field whose name starts with `has_`, since it reserves
    /// `hasX` for presence accessors. Kept to this one place rather than
    /// letting that artifact spread through the UI.
    private(set) var hasApplePrivateEmail = false
    private(set) var plan: Wellspent_V1_AccountPlan = .unspecified
    private(set) var countries: [Country] = []
    private(set) var isLoading = false
    private(set) var isSavingProfile = false
    private(set) var isChangingPassword = false
    private(set) var isDeleting = false
    private(set) var profileErrorMessage: String?
    private(set) var passwordErrorMessage: String?
    private(set) var passwordChangeSucceeded = false

    private let userClient: Wellspent_V1_UserServiceClient
    /// The country list moved to the REST transport, where it is cacheable —
    /// it is the same three rows for every caller on earth and changes roughly
    /// never. Deliberately the *public* REST client even here, on an
    /// authenticated screen: sending a token would make the response look
    /// user-specific to a cache that cannot know otherwise.
    private let restClient: WellSpentREST.Client

    var isUnitedStates: Bool { countryCode == "US" }

    var canSubmitPassword: Bool {
        !currentPassword.isEmpty && RegisterViewModel.passwordError(for: newPassword) == nil && !isChangingPassword
    }

    init(authenticatedClient: ProtocolClient, publicRESTClient: WellSpentREST.Client) {
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.restClient = publicRESTClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let meResponse = userClient.getMe(request: Wellspent_V1_GetMeRequest())
        async let countriesResult = try? restClient.enabledCountries()

        if case .success(let message) = await meResponse.result {
            apply(message.user)
        }
        if let fetched = await countriesResult {
            countries = fetched.filter(\.isEnabled)
        }
    }

    /// Internal (not private) so it's directly testable as a pure prefill
    /// step, without needing a live `GetMe` network call.
    func apply(_ user: Wellspent_V1_User) {
        email = user.email
        hasApplePrivateEmail = user.hasApplePrivateEmail_p
        plan = user.plan
        firstName = user.firstName
        lastName = user.lastName
        countryCode = user.countryCode
        stateCode = user.stateCode
        filingStatus = user.filingStatus
        taxPaymentFrequency = user.taxPaymentFrequency
        language = user.language.isEmpty ? "en" : user.language
        currency = user.currency.isEmpty ? "USD" : user.currency
        AppLanguageStore.apply(language)
    }

    /// Saves the profile and, on success, returns the updated `User` so the
    /// caller can propagate it to `BudgetHomeViewModel` without a refetch.
    func saveProfile() async -> Wellspent_V1_User? {
        isSavingProfile = true
        profileErrorMessage = nil
        defer { isSavingProfile = false }

        let request = Wellspent_V1_UpdateMeRequest.with {
            $0.firstName = firstName
            $0.lastName = lastName
            $0.countryCode = countryCode
            $0.stateCode = isUnitedStates ? stateCode : ""
            $0.filingStatus = isUnitedStates ? filingStatus : .unspecified
            $0.taxPaymentFrequency = isUnitedStates ? taxPaymentFrequency : .unspecified
            $0.language = language
            $0.currency = currency
        }
        let response = await userClient.updateMe(request: request)

        switch response.result {
        case .success(let message):
            apply(message.user)
            return message.user
        case .failure(let error):
            profileErrorMessage = error.message ?? "Couldn't save your profile."
            return nil
        }
    }

    func changePassword() async {
        guard canSubmitPassword else { return }
        isChangingPassword = true
        passwordErrorMessage = nil
        passwordChangeSucceeded = false
        defer { isChangingPassword = false }

        let request = Wellspent_V1_ChangePasswordRequest.with {
            $0.currentPassword = currentPassword
            $0.newPassword = newPassword
        }
        let response = await userClient.changePassword(request: request)

        switch response.result {
        case .success:
            currentPassword = ""
            newPassword = ""
            passwordChangeSucceeded = true
        case .failure(let error):
            passwordErrorMessage = SettingsViewModel.passwordChangeErrorMessage(for: error)
        }
    }

    func deleteAccount() async -> Bool {
        isDeleting = true
        profileErrorMessage = nil
        defer { isDeleting = false }

        let response = await userClient.deleteMe(request: Wellspent_V1_DeleteMeRequest())
        switch response.result {
        case .success:
            return true
        case .failure(let error):
            profileErrorMessage = error.message ?? "Couldn't delete your account."
            return false
        }
    }

    static func passwordChangeErrorMessage(for error: ConnectError) -> String {
        switch error.code {
        case .invalidArgument:
            return error.message ?? "Please check your current password and try again."
        case .unavailable, .deadlineExceeded:
            return "Can't reach the server. Check your connection and try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
