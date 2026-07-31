import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("LoginViewModel")
@MainActor
struct LoginViewModelTests {
    private func makeViewModel() -> LoginViewModel {
        LoginViewModel(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    @Test(
        "accepts well-formed addresses",
        arguments: ["a@b.co", "first.last@example.com", "user+tag@sub.example.com"]
    )
    func validEmails(email: String) {
        #expect(LoginViewModel.isValidEmail(email))
    }

    @Test(
        "rejects malformed addresses",
        arguments: ["", "not-an-email", "missing-domain@", "@missing-local.com", "spaces in@email.com"]
    )
    func invalidEmails(email: String) {
        #expect(!LoginViewModel.isValidEmail(email))
    }

    @Test("submit is disabled until both email and password are present and email is valid")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.email = "not-an-email"
        viewModel.password = "something"
        #expect(!viewModel.canSubmit)

        viewModel.email = "user@example.com"
        #expect(viewModel.canSubmit)

        viewModel.password = ""
        #expect(!viewModel.canSubmit)
    }

    @Test("maps invalidArgument to a generic incorrect-credentials message")
    func mapsInvalidArgument() {
        let message = LoginViewModel.errorMessage(for: ConnectError(code: .invalidArgument, message: "invalid email or password"))
        #expect(message == "Incorrect email or password.")
    }

    @Test("maps permissionDenied to the server's account-status message")
    func mapsPermissionDenied() {
        let message = LoginViewModel.errorMessage(for: ConnectError(code: .permissionDenied, message: "account is deactivated"))
        #expect(message == "account is deactivated")
    }

    @Test("maps unavailable/deadlineExceeded to a connectivity message", arguments: [Code.unavailable, Code.deadlineExceeded])
    func mapsConnectivityErrors(code: Code) {
        let message = LoginViewModel.errorMessage(for: ConnectError(code: code, message: nil))
        #expect(message == "Can't reach the server. Check your connection and try again.")
    }

    @Test("maps any other code to a generic retry message")
    func mapsUnknownErrors() {
        let message = LoginViewModel.errorMessage(for: ConnectError(code: .internalError, message: "boom"))
        #expect(message == "Something went wrong. Please try again.")
    }
}
