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

    /// The country list is served on the REST transport, where it is
    /// cacheable — it is the same three rows for every caller on earth and
    /// changes roughly never. Deliberately the *public* REST client even
    /// here, on an authenticated screen: sending a token would make the
    /// response look user-specific to a cache that cannot know otherwise.
    /// Always Go — the C# backend has no countries endpoint at all, same as
    /// web's `useCountries.ts`.
    private let restClient: WellSpentREST.Client
    /// The C# backend's authenticated client, for GetMe/UpdateMe/ChangePassword/DeleteMe.
    private let csharpAuthenticatedRESTClient: WellSpentREST.Client

    var isUnitedStates: Bool { countryCode == "US" }

    var canSubmitPassword: Bool {
        !currentPassword.isEmpty && RegisterViewModel.passwordError(for: newPassword) == nil && !isChangingPassword
    }

    init(publicRESTClient: WellSpentREST.Client, csharpAuthenticatedRESTClient: WellSpentREST.Client) {
        self.restClient = publicRESTClient
        self.csharpAuthenticatedRESTClient = csharpAuthenticatedRESTClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let user = UserRESTMapping.currentUser(restClient: csharpAuthenticatedRESTClient)
        async let countriesResult = try? restClient.enabledCountries()

        if let user = await user {
            apply(user)
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

        do {
            let output = try await csharpAuthenticatedRESTClient.updateMe(.init(body: .json(.init(
                firstName: firstName,
                lastName: lastName,
                countryCode: countryCode,
                stateCode: isUnitedStates ? stateCode : "",
                filingStatus: isUnitedStates ? filingStatus.rawValue : 0,
                taxPaymentFrequency: isUnitedStates ? taxPaymentFrequency.rawValue : 0,
                language: language,
                currency: currency
            ))))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                profileErrorMessage = "Couldn't save your profile."
                return nil
            }
            let user = UserRESTMapping.proto(from: body.user)
            apply(user)
            return user
        } catch {
            profileErrorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't save your profile."
            return nil
        }
    }

    func changePassword() async {
        guard canSubmitPassword else { return }
        isChangingPassword = true
        passwordErrorMessage = nil
        passwordChangeSucceeded = false
        defer { isChangingPassword = false }

        do {
            let output = try await csharpAuthenticatedRESTClient.changePassword(.init(body: .json(.init(
                currentPassword: currentPassword,
                newPassword: newPassword
            ))))
            switch output {
            case .ok:
                currentPassword = ""
                newPassword = ""
                passwordChangeSucceeded = true
            case .badRequest(let badRequest):
                passwordErrorMessage = (try? badRequest.body.json.message) ?? "Please check your current password and try again."
            default:
                passwordErrorMessage = "Something went wrong. Please try again."
            }
        } catch {
            passwordErrorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Something went wrong. Please try again."
        }
    }

    func deleteAccount() async -> Bool {
        isDeleting = true
        profileErrorMessage = nil
        defer { isDeleting = false }

        do {
            guard case .ok = try await csharpAuthenticatedRESTClient.deleteMe(.init()) else {
                profileErrorMessage = "Couldn't delete your account."
                return false
            }
            return true
        } catch {
            profileErrorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't delete your account."
            return false
        }
    }
}
