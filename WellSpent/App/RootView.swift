import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    /// Non-sensitive (a shareable invite-link token), persisted so it
    /// survives the app being killed mid-login/register — e.g. the user taps
    /// an invite link, switches to Mail, the app gets purged from memory,
    /// then they relaunch it directly instead of re-tapping the link.
    @State private var pendingInviteToken: String? = UserDefaults.standard.string(forKey: RootView.pendingInviteTokenKey) {
        didSet {
            UserDefaults.standard.set(pendingInviteToken, forKey: Self.pendingInviteTokenKey)
        }
    }
    @State private var budgetListRefreshTrigger = 0
    /// Distinct from `pendingInviteToken != nil` — decouples "is there a
    /// pending invite" (persisted data) from "is the cover on screen right
    /// now" (transient UI state), since the Sign In/Register CTAs need to
    /// hide the cover (revealing the already-mounted `LoginView`) *without*
    /// forgetting the pending invite, so it can auto-reappear post-login.
    @State private var isInvitePreviewPresented: Bool = UserDefaults.standard.string(forKey: RootView.pendingInviteTokenKey) != nil

    private static let pendingInviteTokenKey = "pendingInviteToken"

    var body: some View {
        Group {
            if session.isAuthenticated {
                BudgetListView()
                    .id(budgetListRefreshTrigger)
            } else {
                NavigationStack {
                    LoginView(publicClient: session.publicClient)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                session.refreshAuthenticationState()
            }
        }
        .onOpenURL { url in
            // ASWebAuthenticationSession's own completion handler doesn't
            // reliably fire for Universal Link redirects — see
            // GoogleAuthCoordinator's doc comment. This is the real delivery
            // path for the Google sign-in callback.
            if url.path == "/auth/callback" {
                GoogleAuthCoordinator.pendingCallback?(url)
                return
            }
            guard let token = InviteDeepLink.token(from: url) else { return }
            pendingInviteToken = token
            isInvitePreviewPresented = true
        }
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            // Re-present the cover once login/register completes, if the
            // user stepped aside from it via the Sign In/Register CTAs
            // (which hide the cover but deliberately keep the token) —
            // mirrors web's "land back on the invite page, tap Accept
            // again" behavior, just without a full page reload.
            if isAuthenticated, pendingInviteToken != nil {
                isInvitePreviewPresented = true
            }
        }
        .task(id: session.isAuthenticated) {
            // Requesting push permission at cold launch, before the user has
            // even logged in, would be a jarring first-run experience — ask
            // once authenticated instead. `.task(id:)` re-fires on every
            // login (including after a logout/login cycle), which is a
            // harmless re-registration if already authorized.
            guard session.isAuthenticated else { return }
            await PushNotificationRegistrar.requestPermissionIfNeeded()
        }
        .task(id: session.isAuthenticated) {
            // Same "after login, not at cold launch" posture as push —
            // a separate `.task(id:)` block (not folded into the one above)
            // so a future change to either permission's timing doesn't
            // accidentally couple the two.
            guard session.isAuthenticated else { return }
            await TrackingPermission.requestIfNeeded()
        }
        .fullScreenCover(isPresented: $isInvitePreviewPresented) {
            if let pendingInviteToken {
                AcceptInviteView(
                    token: pendingInviteToken,
                    publicClient: session.publicClient,
                    authenticatedClient: session.authenticatedClient,
                    onAccepted: {
                        self.pendingInviteToken = nil
                        isInvitePreviewPresented = false
                        budgetListRefreshTrigger += 1
                    },
                    onDismiss: {
                        // True cancel (toolbar "Close") — forgets the invite
                        // entirely, unlike `onRequestAuth` below.
                        self.pendingInviteToken = nil
                        isInvitePreviewPresented = false
                    },
                    onRequestAuth: {
                        // Sign In / Register — only hides the cover so
                        // `LoginView` (already mounted underneath) becomes
                        // reachable; keeps `pendingInviteToken` so the
                        // `onChange(of: session.isAuthenticated)` above
                        // re-presents this same screen post-login.
                        isInvitePreviewPresented = false
                    }
                )
            }
        }
    }
}

#Preview {
    RootView()
        .environment(SessionStore())
}
