import SwiftUI

/// Full-width "Continue with Apple / Google" buttons under the log-in form.
///
/// Owns both coordinators so the two share one error line. Apple is first:
/// App Store Review 4.8 requires Sign in with Apple in an equivalent-or-better
/// position than any other third-party login.
struct SocialSignInButtons: View {
    @Environment(SessionStore.self) private var session

    @State private var apple: AppleAuthCoordinator?
    @State private var google: GoogleAuthCoordinator?

    private var errorMessage: String? {
        apple?.errorMessage ?? google?.errorMessage
    }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    if apple == nil { apple = AppleAuthCoordinator() }
                    await apple?.signIn(session: session)
                }
            } label: {
                ProviderLabel(title: Text("Continue with Apple"), systemImage: "apple.logo", isBusy: apple?.isSigningIn == true)
            }
            .buttonStyle(AppleSignInButtonStyle())
            .disabled(apple?.isSigningIn == true)
            .accessibilityIdentifier("appleAuthButton")

            Button {
                Task {
                    if google == nil { google = GoogleAuthCoordinator() }
                    await google?.signIn(session: session)
                }
            } label: {
                ProviderLabel(title: Text("Continue with Google"), systemImage: "g.circle", isBusy: google?.isSigningIn == true)
            }
            .buttonStyle(OutlinedActionButtonStyle())
            .disabled(!FeatureFlags.googleAuthEnabled || google?.isSigningIn == true)
            .accessibilityIdentifier("googleAuthButton")

            if let errorMessage {
                InlineErrorBanner(message: errorMessage)
                    .accessibilityIdentifier("socialAuthErrorMessage")
            }
        }
    }
}

private struct ProviderLabel: View {
    let title: Text
    let systemImage: String
    let isBusy: Bool

    var body: some View {
        // The label stays laid out while busy so the button doesn't resize mid-tap.
        ZStack {
            Label { title } icon: { Image(systemName: systemImage) }
                .opacity(isBusy ? 0 : 1)
            if isBusy { ProgressView() }
        }
    }
}

/// Apple's HIG black button, inverted in dark mode.
private struct AppleSignInButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

#Preview {
    SocialSignInButtons()
        .padding()
        .environment(SessionStore())
}
