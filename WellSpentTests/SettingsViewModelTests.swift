import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    private func makeViewModel() -> SettingsViewModel {
        SettingsViewModel(
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            publicRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func makeUser() -> Wellspent_V1_User {
        .with {
            $0.email = "ada@example.com"
            $0.firstName = "Ada"
            $0.lastName = "Lovelace"
            $0.countryCode = "US"
            $0.stateCode = "CA"
            $0.filingStatus = .single
            $0.taxPaymentFrequency = .quarterly
            $0.language = "en"
            $0.currency = "USD"
            $0.plan = .pro
        }
    }

    @Test("apply prefills every field from the fetched user")
    func prefillsFromUser() {
        let viewModel = makeViewModel()
        viewModel.apply(makeUser())

        #expect(viewModel.email == "ada@example.com")
        #expect(viewModel.firstName == "Ada")
        #expect(viewModel.lastName == "Lovelace")
        #expect(viewModel.countryCode == "US")
        #expect(viewModel.stateCode == "CA")
        #expect(viewModel.filingStatus == .single)
        #expect(viewModel.taxPaymentFrequency == .quarterly)
        #expect(viewModel.language == "en")
        #expect(viewModel.currency == "USD")
        #expect(viewModel.plan == .pro)
        #expect(!viewModel.hasApplePrivateEmail)
    }

    // The Settings screen hides the address entirely for these accounts — it's
    // a machine-generated relay alias, so it tells the user nothing.
    @Test("apply carries the backend's Hide My Email flag through")
    func prefillsApplePrivateEmailFlag() {
        let viewModel = makeViewModel()
        var user = makeUser()
        user.email = "a1b2c3d4e5@privaterelay.appleid.com"
        user.hasApplePrivateEmail_p = true

        viewModel.apply(user)

        #expect(viewModel.hasApplePrivateEmail)
    }

    // The flag is the backend's call, not a suffix check repeated here — an
    // ordinary address must never trip it.
    @Test("apply leaves the flag off for an ordinary address")
    func prefillsWithoutApplePrivateEmailFlag() {
        let viewModel = makeViewModel()
        viewModel.apply(makeUser())

        #expect(!viewModel.hasApplePrivateEmail)
    }

    @Test("apply defaults blank language/currency to en/USD, matching the backend's default")
    func prefillDefaultsBlankLanguageAndCurrency() {
        let viewModel = makeViewModel()
        var user = makeUser()
        user.language = ""
        user.currency = ""
        viewModel.apply(user)

        #expect(viewModel.language == "en")
        #expect(viewModel.currency == "USD")
    }

    @Test("isUnitedStates is true only for the US country code")
    func isUnitedStatesReflectsCountryCode() {
        let viewModel = makeViewModel()
        viewModel.countryCode = "US"
        #expect(viewModel.isUnitedStates)

        viewModel.countryCode = "AR"
        #expect(!viewModel.isUnitedStates)
    }

    @Test("canSubmitPassword requires a non-blank current password and a valid new password")
    func canSubmitPasswordReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmitPassword)

        viewModel.currentPassword = "oldpassword"
        #expect(!viewModel.canSubmitPassword) // new password not yet valid

        viewModel.newPassword = "NewValid1!"
        #expect(viewModel.canSubmitPassword)

        viewModel.currentPassword = ""
        #expect(!viewModel.canSubmitPassword)
    }

    @Test("maps invalidArgument to the server's message when present")
    func mapsInvalidArgument() {
        let message = SettingsViewModel.passwordChangeErrorMessage(for: ConnectError(code: .invalidArgument, message: "current password is incorrect"))
        #expect(message == "current password is incorrect")
    }

    @Test("maps connectivity errors to a generic connectivity message")
    func mapsConnectivityErrors() {
        let message = SettingsViewModel.passwordChangeErrorMessage(for: ConnectError(code: .unavailable, message: nil))
        #expect(message.contains("connection"))
    }
}
