import SwiftUI

/// Compact, logo-only button for a third-party sign-in provider.
///
/// Purely presentational — it knows nothing about any provider's flow, so the
/// Apple and Google buttons can't drift apart in size, shape, or disabled
/// treatment the way two independently-styled buttons would.
///
/// 44pt tall to meet the minimum tap target; the logo is the only content, so
/// `accessibilityLabel` carries the meaning for VoiceOver.
struct AuthProviderIconButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Kept in the layout while busy so the row doesn't resize
                // mid-tap.
                Image(systemName: systemImage)
                    .font(.title2)
                    .opacity(isBusy ? 0 : 1)

                if isBusy {
                    ProgressView()
                }
            }
            .frame(width: 64, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    HStack(spacing: 12) {
        AuthProviderIconButton(systemImage: "apple.logo", accessibilityLabel: "Sign in with Apple") {}
        AuthProviderIconButton(systemImage: "g.circle", accessibilityLabel: "Continue with Google") {}
        AuthProviderIconButton(systemImage: "g.circle", accessibilityLabel: "Continue with Google", isBusy: true) {}
        AuthProviderIconButton(systemImage: "g.circle", accessibilityLabel: "Continue with Google", isDisabled: true) {}
    }
    .padding()
}
