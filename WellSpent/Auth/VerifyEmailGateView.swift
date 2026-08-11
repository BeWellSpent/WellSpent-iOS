import Observation
import SwiftUI
import WellSpentAPI
import os

@MainActor
@Observable
final class VerifyEmailGateViewModel {
    /// What the gate should do right now. `.unknown` is the pre-first-load
    /// state: the app renders normally through it, so a verified user never
    /// gets a verification wall flashed at them on launch.
    enum State: Equatable {
        case unknown
        case verified
        case unverified(email: String)
    }

    private(set) var state: State = .unknown
    private(set) var isResending = false
    private(set) var cooldownEndsAt: Date?
    private(set) var errorMessage: String?

    private(set) var isChangingEmail = false
    var newEmail = ""
    private(set) var isSavingEmail = false
    private(set) var changeEmailErrorMessage: String?

    private let userClient: Wellspent_V1_UserServiceClient
    private let authClient: Wellspent_V1_AuthServiceClient

    private static let logger = AppLogger.logger("VerifyEmailGate")

    /// Matches the backend's 60-second resend throttle
    /// (see docs/features/email-verification.md).
    private static let resendCooldown: TimeInterval = 60

    var isInCooldown: Bool {
        guard let cooldownEndsAt else { return false }
        return cooldownEndsAt > Date()
    }

    var email: String {
        if case .unverified(let email) = state { return email }
        return ""
    }

    /// Mirrors the backend's ChangeEmail preconditions so an obviously bad
    /// value never costs a round trip. The backend rejects an unchanged
    /// address rather than succeeding silently, so that case is blocked here
    /// too — a "saved" with no mail arriving reads as a broken feature.
    var canSubmitEmailChange: Bool {
        VerifyEmailGateViewModel.isValidEmail(newEmail)
            && VerifyEmailGateViewModel.normalize(newEmail) != VerifyEmailGateViewModel.normalize(email)
            && !isSavingEmail
    }

    init(authenticatedClient: ProtocolClient, publicClient: ProtocolClient) {
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.authClient = Wellspent_V1_AuthServiceClient(client: publicClient)
    }

    /// Re-reads verification status. Called on appear and every time the app
    /// returns to the foreground — the verification link opens in a browser,
    /// so coming back is exactly when the answer may have changed.
    func refresh() async {
        let response = await userClient.getMe(request: Wellspent_V1_GetMeRequest())
        switch response.result {
        case .success(let message):
            apply(message.user)
        case .failure(let error):
            // Deliberately leaves `state` alone. A failed check must not
            // promote an unverified account to verified, and must not lock a
            // verified one out over a dropped connection.
            Self.logger.error("verifyGate.getMe failed: \(error.message ?? "unknown", privacy: .public)")
        }
    }

    /// Internal (not private) so the state mapping is testable as a pure step,
    /// without a live GetMe — same posture as `SettingsViewModel.apply`.
    func apply(_ user: Wellspent_V1_User) {
        state = user.isVerified ? .verified : .unverified(email: user.email)
    }

    func resend() async {
        guard !isResending, !isInCooldown else { return }
        isResending = true
        errorMessage = nil
        defer { isResending = false }

        let request = Wellspent_V1_ResendVerificationEmailRequest.with { $0.email = email }
        let response = await authClient.resendVerificationEmail(request: request)

        switch response.result {
        case .success:
            cooldownEndsAt = Date().addingTimeInterval(Self.resendCooldown)
        case .failure(let error):
            Self.logger.error("verifyGate.resend failed: \(error.message ?? "unknown", privacy: .public)")
            errorMessage = error.message ?? String(
                localized: "Couldn't resend the email. Try again in a moment.",
                locale: AppLanguageStore.currentLocale
            )
        }
    }

    func beginChangingEmail() {
        isChangingEmail = true
        newEmail = ""
        changeEmailErrorMessage = nil
    }

    func cancelChangingEmail() {
        isChangingEmail = false
        newEmail = ""
        changeEmailErrorMessage = nil
    }

    /// Corrects an address mistyped at registration — the only way out of the
    /// gate when resend can only ever reach the same wrong inbox.
    func changeEmail() async {
        guard canSubmitEmailChange else { return }
        isSavingEmail = true
        changeEmailErrorMessage = nil
        defer { isSavingEmail = false }

        let request = Wellspent_V1_ChangeEmailRequest.with { $0.newEmail = newEmail }
        let response = await userClient.changeEmail(request: request)

        switch response.result {
        case .success(let message):
            // The backend has already sent a fresh link to the new address,
            // so the cooldown restarts from here rather than from whatever
            // the previous resend left behind.
            apply(message.user)
            cooldownEndsAt = Date().addingTimeInterval(Self.resendCooldown)
            isChangingEmail = false
            newEmail = ""
        case .failure(let error):
            Self.logger.error("verifyGate.changeEmail failed: \(error.message ?? "unknown", privacy: .public)")
            changeEmailErrorMessage = error.message ?? String(
                localized: "Couldn't change your email address. Try again.",
                locale: AppLanguageStore.currentLocale
            )
        }
    }

    nonisolated static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Deliberately loose — the backend's own parse is the real check. This
    /// only keeps the button disabled on obvious nonsense.
    nonisolated static func isValidEmail(_ raw: String) -> Bool {
        let email = normalize(raw)
        guard !email.contains(" "), email.count >= 5 else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

/// Replaces the whole authenticated app while the account's email is
/// unverified. Presented as a full screen rather than a sheet or cover
/// specifically so there is nothing to swipe away — the only ways past it are
/// verifying, correcting the address, or logging out.
///
/// Google and Apple sign-ups are verified at creation and never see this.
struct VerifyEmailGateView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var viewModel: VerifyEmailGateViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("We sent a verification link to \(viewModel.email). Confirm your address to start using WellSpent. The link expires in 10 minutes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await viewModel.resend() }
                    } label: {
                        HStack {
                            viewModel.isInCooldown ? Text("Email sent") : Text("Resend verification email")
                            if viewModel.isResending {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isResending || viewModel.isInCooldown)
                    .accessibilityIdentifier("resendVerificationButton")

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("verifyGateErrorMessage")
                    }
                }

                changeEmailSection

                Section {
                    Button("Log out", role: .destructive) {
                        session.endSession()
                    }
                    .accessibilityIdentifier("verifyGateLogoutButton")
                }
            }
            .navigationTitle("Verify your email")
        }
    }

    @ViewBuilder
    private var changeEmailSection: some View {
        if viewModel.isChangingEmail {
            Section {
                TextField("New email address", text: $viewModel.newEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("verifyGateNewEmailField")

                if let changeEmailErrorMessage = viewModel.changeEmailErrorMessage {
                    Text(changeEmailErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("verifyGateChangeEmailErrorMessage")
                }

                Button {
                    Task { await viewModel.changeEmail() }
                } label: {
                    HStack {
                        Text("Save and resend")
                        if viewModel.isSavingEmail {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!viewModel.canSubmitEmailChange)
                .accessibilityIdentifier("verifyGateSaveEmailButton")

                Button("Cancel", role: .cancel) {
                    viewModel.cancelChangingEmail()
                }
                .disabled(viewModel.isSavingEmail)
            } header: {
                Text("Change email address")
            } footer: {
                Text("We'll send a new verification link to this address.")
            }
        } else {
            Section {
                Button("Wrong email address? Change it") {
                    viewModel.beginChangingEmail()
                }
                .accessibilityIdentifier("verifyGateChangeEmailButton")
            }
        }
    }
}

#Preview {
    VerifyEmailGateView(
        viewModel: {
            let viewModel = VerifyEmailGateViewModel(
                authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
                publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
            )
            viewModel.apply(.with {
                $0.email = "typo@exmaple.com"
                $0.isVerified = false
            })
            return viewModel
        }()
    )
    .environment(SessionStore())
}
