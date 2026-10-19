import Testing
@testable import WellSpent

@Suite("LoginViewModel")
@MainActor
struct LoginViewModelTests {
    private func makeViewModel() -> LoginViewModel {
        LoginViewModel()
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
}
