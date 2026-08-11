import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("VerifyEmailGateViewModel")
@MainActor
struct VerifyEmailGateViewModelTests {
    private func makeViewModel() -> VerifyEmailGateViewModel {
        let client = APIClient.makePublicClient(baseURL: "http://localhost:1")
        return VerifyEmailGateViewModel(authenticatedClient: client, publicClient: client)
    }

    private func makeUser(email: String = "ada@example.com", verified: Bool) -> Wellspent_V1_User {
        .with {
            $0.email = email
            $0.isVerified = verified
        }
    }

    // Unknown must render the app, not a verification wall — otherwise every
    // verified user gets the gate flashed at them on launch.
    @Test("starts in the unknown state so the app renders until GetMe answers")
    func startsUnknown() {
        #expect(makeViewModel().state == .unknown)
    }

    @Test("apply maps an unverified user to the gated state, carrying the address")
    func appliesUnverifiedUser() {
        let viewModel = makeViewModel()

        viewModel.apply(makeUser(email: "typo@exmaple.com", verified: false))

        #expect(viewModel.state == .unverified(email: "typo@exmaple.com"))
        #expect(viewModel.email == "typo@exmaple.com")
    }

    @Test("apply maps a verified user through")
    func appliesVerifiedUser() {
        let viewModel = makeViewModel()

        viewModel.apply(makeUser(verified: true))

        #expect(viewModel.state == .verified)
        #expect(viewModel.email.isEmpty)
    }

    @Test("isInCooldown is false until a resend actually succeeds")
    func cooldownStartsClear() {
        #expect(!makeViewModel().isInCooldown)
    }

    @Test("canSubmitEmailChange accepts a valid address that differs from the current one")
    func allowsCorrectedAddress() {
        let viewModel = makeViewModel()
        viewModel.apply(makeUser(email: "typo@exmaple.com", verified: false))

        viewModel.newEmail = "correct@example.com"

        #expect(viewModel.canSubmitEmailChange)
    }

    // The backend rejects an unchanged address rather than succeeding
    // silently, so blocking it here turns a confusing error into a disabled
    // button — including when it differs only by case or whitespace.
    @Test("canSubmitEmailChange blocks the address already on the account")
    func blocksUnchangedAddress() {
        let viewModel = makeViewModel()
        viewModel.apply(makeUser(email: "same@example.com", verified: false))

        viewModel.newEmail = "same@example.com"
        #expect(!viewModel.canSubmitEmailChange)

        viewModel.newEmail = "  SAME@Example.com "
        #expect(!viewModel.canSubmitEmailChange)
    }

    @Test("canSubmitEmailChange blocks a malformed address")
    func blocksMalformedAddress() {
        let viewModel = makeViewModel()
        viewModel.apply(makeUser(email: "typo@exmaple.com", verified: false))

        for candidate in ["", "   ", "not-an-email", "@example.com", "user@", "user@example", "a b@example.com"] {
            viewModel.newEmail = candidate
            #expect(!viewModel.canSubmitEmailChange, "\(candidate) must not be submittable")
        }
    }

    @Test("isValidEmail accepts ordinary addresses")
    func acceptsOrdinaryAddresses() {
        for candidate in ["ada@example.com", "  Ada@Example.COM  ", "a.b+tag@sub.example.co.uk"] {
            #expect(VerifyEmailGateViewModel.isValidEmail(candidate), "\(candidate) must be valid")
        }
    }

    @Test("normalize lowercases and trims, matching what the backend stores")
    func normalizesLikeTheBackend() {
        #expect(VerifyEmailGateViewModel.normalize("  Ada@Example.COM ") == "ada@example.com")
    }

    @Test("beginChangingEmail opens the form and cancel clears it")
    func togglesTheChangeEmailForm() {
        let viewModel = makeViewModel()

        viewModel.beginChangingEmail()
        #expect(viewModel.isChangingEmail)

        viewModel.newEmail = "typed@example.com"
        viewModel.cancelChangingEmail()

        #expect(!viewModel.isChangingEmail)
        #expect(viewModel.newEmail.isEmpty, "a cancelled draft must not survive into the next attempt")
    }
}
