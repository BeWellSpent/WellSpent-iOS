import Foundation
import Observation
import WellSpentREST

/// Backs the status banner shown above the whole app.
///
/// Uses the *public* client, not the authenticated one: the endpoint takes no
/// token, so a signed-out user staring at a broken login screen still gets the
/// notice — during an outage that is most of the point.
///
/// Served over REST rather than Connect so the response is genuinely cacheable.
/// It carries `public, max-age=30` and an ETag, so `URLSession` revalidates on
/// its own and the common "nothing is live" answer usually costs a conditional
/// request rather than a full round trip.
@MainActor
@Observable
final class StatusBannerViewModel {
    private(set) var banner: StatusBanner?
    private(set) var isExpanded = false

    /// Mirrored into observable state rather than read straight from the store
    /// on each access: `UserDefaults` is invisible to `@Observable`, so a view
    /// reading through it would never re-render when a banner is dismissed.
    private(set) var dismissedIDs: Set<String>

    private let client: WellSpentREST.Client
    private let dismissals: StatusBannerDismissalStore

    init(publicClient: WellSpentREST.Client, dismissals: StatusBannerDismissalStore = StatusBannerDismissalStore()) {
        self.client = publicClient
        self.dismissals = dismissals
        self.dismissedIDs = Set(dismissals.dismissedIDs())
    }

    /// The banner to actually render — nil when nothing is live or the reader
    /// has already closed this one.
    var visibleBanner: StatusBanner? {
        guard let banner, !banner.id.isEmpty else { return nil }
        guard !dismissedIDs.contains(banner.id) else { return nil }
        return banner
    }

    func load() async {
        do {
            let next = try await client.activeStatusBanner()
            // Collapse whenever the banner changes, so a new message never
            // inherits the previous one's expanded state.
            if next?.id != banner?.id { isExpanded = false }
            banner = next
        } catch {
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
    func setStateForTesting(banner: StatusBanner?) {
        self.banner = banner
    }
}
