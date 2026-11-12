import Observation
import SwiftUI
import WellSpentAPI
import WellSpentREST
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

    private let publicRESTClient: WellSpentREST.Client
    private let authenticatedRESTClient: WellSpentREST.Client

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

    init(publicRESTClient: WellSpentREST.Client, authenticatedRESTClient: WellSpentREST.Client) {
        self.publicRESTClient = publicRESTClient
        self.authenticatedRESTClient = authenticatedRESTClient
    }

    /// Re-reads verification status. Called on appear and every time the app
    /// returns to the foreground — the verification link opens in a browser,
    /// so coming back is exactly when the answer may have changed.
    func refresh() async {
        // Deliberately leaves `state` alone on failure either way. A failed
        // check must not promote an unverified account to verified, and must
        // not lock a verified one out over a dropped connection.
        guard let user = await UserRESTMapping.currentUser(restClient: authenticatedRESTClient) else {
            Self.logger.error("verifyGate.getMe failed")
            return
        }
        apply(user)
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

        let fallback = String(localized: "Couldn't resend the email. Try again in a moment.", locale: AppLanguageStore.currentLocale)
        do {
            let output = try await publicRESTClient.resendVerificationEmail(.init(body: .json(.init(email: email))))
            switch output {
            case .ok:
                cooldownEndsAt = Date().addingTimeInterval(Self.resendCooldown)
            case .badRequest(let badRequest):
                // Only 400 case is the cooldown — pass the server's message through.
                let message = (try? badRequest.body.json.message) ?? fallback
                Self.logger.error("verifyGate.resend REST failed: \(message, privacy: .public)")
                errorMessage = message
            default:
                Self.logger.error("verifyGate.resend REST failed with an unexpected response")
                errorMessage = fallback
            }
        } catch {
            Self.logger.error("verifyGate.resend REST failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
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

        let fallback = String(localized: "Couldn't change your email address. Try again.", locale: AppLanguageStore.currentLocale)
        do {
            let output = try await authenticatedRESTClient.changeEmail(.init(body: .json(.init(newEmail: newEmail))))
            switch output {
            case .ok(let ok):
                guard let body = try? ok.body.json else { changeEmailErrorMessage = fallback; return }
                apply(UserRESTMapping.proto(from: body.user))
                cooldownEndsAt = Date().addingTimeInterval(Self.resendCooldown)
                isChangingEmail = false
                newEmail = ""
            case .badRequest(let badRequest):
                changeEmailErrorMessage = (try? badRequest.body.json.message) ?? fallback
            case .conflict:
                changeEmailErrorMessage = String(localized: "That email address is already in use.", locale: AppLanguageStore.currentLocale)
            default:
                changeEmailErrorMessage = fallback
            }
        } catch {
            Self.logger.error("verifyGate.changeEmail REST failed: \(error.localizedDescription, privacy: .public)")
            changeEmailErrorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
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
    @Environment(\.openURL) private var openURL
    @Bindable var viewModel: VerifyEmailGateViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "envelope")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                        .accessibilityHidden(true)

                    OnboardingHeading(
                        title: Text("Check your inbox"),
                        subtitle: Text("Tap the link we sent to confirm your email. Come back here afterwards and you'll go straight in.")
                    )
                    .padding(.bottom, 8)

                    sentToCard

                    Text("Not there? Check spam or promotions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("BrandMark")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log out") { session.endSession() }
                        .accessibilityIdentifier("verifyGateLogoutButton")
                }
            }
            .pinnedActionBar {
                Button("Open Mail") {
                    // The Mail app's own scheme opens its inbox, not a compose sheet.
                    if let url = URL(string: "message://") { openURL(url) }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("verifyGateOpenMailButton")

                resendButton
            }
        }
    }

    private var sentToCard: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isChangingEmail {
                    changeEmailForm
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sent to")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(verbatim: viewModel.email)
                            .font(.headline)
                    }

                    Label("The link works for 10 minutes.", systemImage: "clock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    if let errorMessage = viewModel.errorMessage {
                        InlineErrorBanner(message: errorMessage)
                            .accessibilityIdentifier("verifyGateErrorMessage")
                    }

                    Button {
                        viewModel.beginChangingEmail()
                    } label: {
                        HStack {
                            Text("Wrong address? Change it")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("verifyGateChangeEmailButton")
                }
            }
        }
    }

    @ViewBuilder
    private var changeEmailForm: some View {
        LabeledFieldBox(label: Text("New email address"), footnote: Text("We'll send a new verification link to this address.")) {
            TextField("New email address", text: $viewModel.newEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("verifyGateNewEmailField")
        }

        if let changeEmailErrorMessage = viewModel.changeEmailErrorMessage {
            InlineErrorBanner(message: changeEmailErrorMessage)
                .accessibilityIdentifier("verifyGateChangeEmailErrorMessage")
        }

        Button {
            Task { await viewModel.changeEmail() }
        } label: {
            if viewModel.isSavingEmail {
                ProgressView()
            } else {
                Text("Save and resend")
            }
        }
        .buttonStyle(TintedActionButtonStyle())
        .disabled(!viewModel.canSubmitEmailChange)
        .accessibilityIdentifier("verifyGateSaveEmailButton")

        Button("Cancel", role: .cancel) {
            viewModel.cancelChangingEmail()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(viewModel.isSavingEmail)
    }

    /// Counts down the 60-second cooldown instead of a static "Email sent".
    private var resendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int((viewModel.cooldownEndsAt?.timeIntervalSince(context.date) ?? 0).rounded(.up))
            Button {
                Task { await viewModel.resend() }
            } label: {
                if viewModel.isResending {
                    ProgressView()
                } else if remaining > 0 {
                    Text("Resend in \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))")
                        .monospacedDigit()
                } else {
                    Text("Resend email")
                }
            }
            .buttonStyle(OutlinedActionButtonStyle())
            .disabled(viewModel.isResending || remaining > 0)
            .accessibilityIdentifier("resendVerificationButton")
        }
    }
}

#Preview {
    VerifyEmailGateView(
        viewModel: {
            let viewModel = VerifyEmailGateViewModel(
                publicRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
                authenticatedRESTClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
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
