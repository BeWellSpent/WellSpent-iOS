import SwiftUI
import UIKit

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
    @State private var budgetHomeRefreshTrigger = 0
    /// Distinct from `pendingInviteToken != nil` — decouples "is there a
    /// pending invite" (persisted data) from "is the cover on screen right
    /// now" (transient UI state), since the Sign In/Register CTAs need to
    /// hide the cover (revealing the already-mounted `LoginView`) *without*
    /// forgetting the pending invite, so it can auto-reappear post-login.
    @State private var isInvitePreviewPresented: Bool = UserDefaults.standard.string(forKey: RootView.pendingInviteTokenKey) != nil
    /// Created once per session, on first authenticated render. Lives here
    /// rather than inside the gate view so its state survives the gate being
    /// swapped out and back in (e.g. a failed refresh) without re-fetching.
    @State private var verifyGateViewModel: VerifyEmailGateViewModel?
    /// Built from the *public* client, so the banner works signed out — an
    /// outage notice has to reach someone stuck on the login screen.
    @State private var statusBannerViewModel: StatusBannerViewModel?

    private static let pendingInviteTokenKey = "pendingInviteToken"

    /// True only once GetMe has actually said the account is unverified.
    /// Unknown (pre-first-load, or a failed check) deliberately renders the
    /// app rather than a verification wall.
    private var isEmailUnverified: Bool {
        if case .unverified = verifyGateViewModel?.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            if let statusBannerViewModel {
                StatusBannerView(viewModel: statusBannerViewModel)
            }
            content
        }
        .task {
            // Created here rather than in an initialiser so it survives the
            // authenticated/unauthenticated swap below — the banner is the one
            // thing on screen that shouldn't reset when you log in or out.
            if statusBannerViewModel == nil {
                statusBannerViewModel = StatusBannerViewModel(publicClient: session.publicRESTClient)
            }
            await statusBannerViewModel?.load()
        }
    }

    private var content: some View {
        Group {
            if session.isAuthenticated {
                if let verifyGateViewModel, isEmailUnverified {
                    // Replaces the app outright instead of covering it: a
                    // sheet or fullScreenCover can be swiped away, and this
                    // view already presents the invite cover — a second
                    // presentation modifier on one view is the footgun that
                    // caused the Plaid double-tap bug.
                    VerifyEmailGateView(viewModel: verifyGateViewModel)
                } else {
                    BudgetHomeView()
                        .id(budgetHomeRefreshTrigger)
                }
            } else {
                NavigationStack {
                    LoginView(publicClient: session.publicClient)
                }
            }
        }
        .task(id: session.isAuthenticated) {
            // The verification link opens in a browser, so the answer changes
            // outside the app entirely — check on every login, and again on
            // every foreground below.
            guard session.isAuthenticated, let authenticatedClient = session.authenticatedClient else {
                verifyGateViewModel = nil
                return
            }
            if verifyGateViewModel == nil {
                verifyGateViewModel = VerifyEmailGateViewModel(
                    authenticatedClient: authenticatedClient,
                    publicClient: session.publicClient
                )
            }
            await verifyGateViewModel?.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                session.refreshAuthenticationState()
                // Coming back from the browser after tapping the link is
                // exactly the moment verification status may have changed.
                Task { await verifyGateViewModel?.refresh() }
                // Foregrounding is the only cheap re-check the banner gets —
                // there's no polling here, unlike web, since a backgrounded
                // app isn't showing anything to refresh.
                Task { await statusBannerViewModel?.load() }
                // Opening the app (including via a tapped notification, which
                // also lands here) should clear the Home Screen badge — the
                // backend always sends a flat `badge: 1` per push, so nothing
                // else ever resets it.
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
        }
        .onOpenURL { url in
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
        // Suppressed while the gate is up, so an invite can't be accepted
        // around it. The token is kept, not discarded, so the cover returns
        // on its own once the account verifies.
        .fullScreenCover(isPresented: Binding(
            get: { isInvitePreviewPresented && !isEmailUnverified },
            set: { isInvitePreviewPresented = $0 }
        )) {
            if let pendingInviteToken {
                AcceptInviteView(
                    token: pendingInviteToken,
                    publicClient: session.publicClient,
                    authenticatedClient: session.authenticatedClient,
                    onAccepted: {
                        self.pendingInviteToken = nil
                        isInvitePreviewPresented = false
                        budgetHomeRefreshTrigger += 1
                    },
                    onDismiss: {
                        // True cancel (the toolbar ✕) — forgets the invite
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
