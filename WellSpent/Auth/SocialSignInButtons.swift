import SwiftUI
import WellSpentAPI

/// The third-party sign-in options, side by side, shown on both Login and
/// Register.
///
/// Owns both coordinators so the two buttons share one error line — previously
/// each provider's button carried its own, which stacked awkwardly once they
/// sat on the same row.
///
/// Apple is first: App Store Review 4.8 requires Sign in with Apple to be
/// offered in an equivalent-or-better position than any other third-party
/// login. Both use the compact logo-only treatment, which the Sign in with
/// Apple HIG permits where space is constrained.
struct SocialSignInButtons: View {
    @Environment(SessionStore.self) private var session
    let publicClient: ProtocolClient

    @State private var apple: AppleAuthCoordinator?
    @State private var google: GoogleAuthCoordinator?

    private var errorMessage: String? {
        apple?.errorMessage ?? google?.errorMessage
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                AuthProviderIconButton(
                    systemImage: "apple.logo",
                    accessibilityLabel: "Sign in with Apple",
                    isBusy: apple?.isSigningIn == true
                ) {
                    Task {
                        if apple == nil {
                            apple = AppleAuthCoordinator(publicClient: publicClient)
                        }
                        await apple?.signIn(session: session)
                    }
                }
                .accessibilityIdentifier("appleAuthButton")

                AuthProviderIconButton(
                    systemImage: "g.circle",
                    accessibilityLabel: "Continue with Google",
                    isBusy: google?.isSigningIn == true,
                    isDisabled: !FeatureFlags.googleAuthEnabled
                ) {
                    Task {
                        if google == nil {
                            google = GoogleAuthCoordinator(publicClient: publicClient)
                        }
                        await google?.signIn(session: session)
                    }
                }
                .accessibilityIdentifier("googleAuthButton")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("socialAuthErrorMessage")
            }
        }
        // Centers the row regardless of how wide the parent form makes this —
        // the VStack's default center alignment only matters once it actually
        // spans the available width.
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SocialSignInButtons(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
        .padding()
        .environment(SessionStore())
}
