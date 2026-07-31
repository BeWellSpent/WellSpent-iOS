import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isAuthenticated {
                BudgetListView()
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
    }
}
