import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("RegisterViewModel")
@MainActor
struct RegisterViewModelTests {
    private func makeViewModel() -> RegisterViewModel {
        RegisterViewModel(
            publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            publicRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    // MARK: passwordError — mirrors the backend's validatePassword exactly

    @Test("rejects passwords shorter than 8 characters")
    func rejectsTooShort() {
        #expect(RegisterViewModel.passwordError(for: "Ab1!") != nil)
    }

    @Test("rejects passwords missing an uppercase letter")
    func rejectsMissingUppercase() {
        #expect(RegisterViewModel.passwordError(for: "lowercase1!") != nil)
    }

    @Test("rejects passwords missing a lowercase letter")
    func rejectsMissingLowercase() {
        #expect(RegisterViewModel.passwordError(for: "UPPERCASE1!") != nil)
    }

    @Test("rejects passwords missing a digit")
    func rejectsMissingDigit() {
        #expect(RegisterViewModel.passwordError(for: "NoDigitsHere!") != nil)
    }

    @Test("rejects passwords missing a special character")
    func rejectsMissingSpecialCharacter() {
        #expect(RegisterViewModel.passwordError(for: "NoSpecial123") != nil)
    }

    @Test("accepts a password satisfying every rule")
    func acceptsValidPassword() {
        #expect(RegisterViewModel.passwordError(for: "Valid1Password!") == nil)
    }

    // MARK: canSubmit

    @Test("submit is disabled until every required field is valid")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.email = "user@example.com"
        viewModel.password = "Valid1Password!"
        #expect(!viewModel.canSubmit) // still missing first/last name

        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        #expect(viewModel.canSubmit)

        viewModel.firstName = "   "
        #expect(!viewModel.canSubmit) // whitespace-only doesn't count
    }

    // MARK: isUnitedStates

    @Test("isUnitedStates is true only for the US country code")
    func isUnitedStatesReflectsCountryCode() {
        let viewModel = makeViewModel()
        viewModel.countryCode = "US"
        #expect(viewModel.isUnitedStates)

        viewModel.countryCode = "AR"
        #expect(!viewModel.isUnitedStates)
    }

    // MARK: error mapping

    @Test("maps alreadyExists to a duplicate-account message")
    func mapsAlreadyExists() {
        let message = RegisterViewModel.errorMessage(for: ConnectError(code: .alreadyExists, message: nil))
        #expect(message == "An account with that email already exists.")
    }

    @Test("maps invalidArgument to the server's validation message when present")
    func mapsInvalidArgument() {
        let message = RegisterViewModel.errorMessage(for: ConnectError(code: .invalidArgument, message: "password must be at least 8 characters"))
        #expect(message == "password must be at least 8 characters")
    }
}
