import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var pendingInviteToken: String?
    @State private var budgetListRefreshTrigger = 0

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
            pendingInviteToken = InviteDeepLink.token(from: url)
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
        .fullScreenCover(isPresented: Binding(
            get: { session.isAuthenticated && pendingInviteToken != nil },
            set: { if !$0 { pendingInviteToken = nil } }
        )) {
            if let pendingInviteToken, let authenticatedClient = session.authenticatedClient {
                AcceptInviteView(
                    token: pendingInviteToken,
                    publicClient: session.publicClient,
                    authenticatedClient: authenticatedClient,
                    onAccepted: {
                        self.pendingInviteToken = nil
                        budgetListRefreshTrigger += 1
                    },
                    onDismiss: {
                        self.pendingInviteToken = nil
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
