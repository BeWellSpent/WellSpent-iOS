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
