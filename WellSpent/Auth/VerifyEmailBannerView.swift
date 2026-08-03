import Observation
import SwiftUI
import WellSpentAPI

@MainActor
@Observable
final class VerifyEmailBannerViewModel {
    private(set) var isResending = false
    private(set) var cooldownEndsAt: Date?
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_AuthServiceClient
    private let email: String

    /// Matches the backend's 60-second resend cooldown (see
    /// docs/features/email-verification.md).
    var isInCooldown: Bool {
        guard let cooldownEndsAt else { return false }
        return cooldownEndsAt > Date()
    }

    init(publicClient: ProtocolClient, email: String) {
        self.client = Wellspent_V1_AuthServiceClient(client: publicClient)
        self.email = email
    }

    func resend() async {
        guard !isResending, !isInCooldown else { return }
        isResending = true
        errorMessage = nil
        defer { isResending = false }

        let request = Wellspent_V1_ResendVerificationEmailRequest.with { $0.email = email }
        let response = await client.resendVerificationEmail(request: request)

        switch response.result {
        case .success:
            cooldownEndsAt = Date().addingTimeInterval(60)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't resend the email. Try again in a moment."
        }
    }
}

/// Shown on the authenticated screen while `GetMe().user.isVerified == false`.
/// Verification is informational only (see docs/features/email-verification.md)
/// — the user can keep using the app either way, this is just a reminder.
struct VerifyEmailBannerView: View {
    @State private var viewModel: VerifyEmailBannerViewModel

    init(publicClient: ProtocolClient, email: String) {
        _viewModel = State(initialValue: VerifyEmailBannerViewModel(publicClient: publicClient, email: email))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Please verify your email address.")
                .font(.subheadline)

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.resend() }
                } label: {
                    viewModel.isInCooldown ? Text("Email sent") : Text("Resend email")
                }
                .disabled(viewModel.isResending || viewModel.isInCooldown)
                .accessibilityIdentifier("resendVerificationButton")

                if viewModel.isResending {
                    ProgressView()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        // No container-level identifier here — a parent-level identifier can
        // bleed down and override a child button's own identifier under
        // XCUITest. UI tests key off resendVerificationButton directly.
    }
}

#Preview {
    VerifyEmailBannerView(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"), email: "user@example.com")
        .padding()
}
