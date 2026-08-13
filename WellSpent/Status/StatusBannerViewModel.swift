import Foundation
import Observation
import WellSpentAPI

/// Backs the status banner shown above the whole app.
///
/// Uses the *public* client, not the authenticated one: `GetActiveStatusBanner`
/// is auth-bypassed so a signed-out user staring at a broken login screen still
/// gets the notice, which during an outage is most of the point.
@MainActor
@Observable
final class StatusBannerViewModel {
    private(set) var banner: Wellspent_V1_StatusBanner?
    private(set) var isExpanded = false

    /// Mirrored into observable state rather than read straight from the store
    /// on each access: `UserDefaults` is invisible to `@Observable`, so a view
    /// reading through it would never re-render when a banner is dismissed.
    private(set) var dismissedIDs: Set<String>

    private let statusClient: Wellspent_V1_StatusServiceClient
    private let dismissals: StatusBannerDismissalStore

    init(publicClient: ProtocolClient, dismissals: StatusBannerDismissalStore = StatusBannerDismissalStore()) {
        self.statusClient = Wellspent_V1_StatusServiceClient(client: publicClient)
        self.dismissals = dismissals
        self.dismissedIDs = Set(dismissals.dismissedIDs())
    }

    /// The banner to actually render — nil when nothing is live or the reader
    /// has already closed this one.
    var visibleBanner: Wellspent_V1_StatusBanner? {
        guard let banner, !banner.id.isEmpty else { return nil }
        guard !dismissedIDs.contains(banner.id) else { return nil }
        return banner
    }

    func load() async {
        let response = await statusClient.getActiveStatusBanner(request: Wellspent_V1_GetActiveStatusBannerRequest())
        switch response.result {
        case .success(let message):
            let next: Wellspent_V1_StatusBanner? = message.hasBanner ? message.banner : nil
            // Collapse whenever the banner changes, so a new message never
            // inherits the previous one's expanded state.
            if next?.id != banner?.id { isExpanded = false }
            banner = next
        case .failure:
            // Swallowed on purpose. This sits on top of an app that works fine
            // without it, and an unreachable backend already shows itself
            // everywhere else — a second error here helps nobody.
            banner = nil
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func dismiss() {
        guard let banner else { return }
        dismissals.markDismissed(banner.id)
        dismissedIDs.insert(banner.id)
        isExpanded = false
    }

    /// Not private, so rendering and dismissal are testable without a live RPC.
    func setStateForTesting(banner: Wellspent_V1_StatusBanner?) {
        self.banner = banner
    }
}
