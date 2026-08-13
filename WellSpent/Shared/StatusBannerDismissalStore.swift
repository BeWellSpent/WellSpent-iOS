import Foundation

/// Remembers which banners the reader has already closed.
///
/// Kept on-device on purpose, matching web. Storing it per-user would need a
/// table and an authenticated RPC, and would still fail for signed-out users —
/// who are exactly the people reading an outage banner. The trade-off is that a
/// dismissal doesn't follow you to another device.
nonisolated struct StatusBannerDismissalStore {
    private let defaults: UserDefaults
    private static let storageKey = "statusBannerDismissed"

    /// How many IDs to remember. One capped list rather than one key per
    /// banner, so this can't grow without bound over the life of an install.
    /// Only one banner is ever live, so a short history is plenty — an ID
    /// falling off the end belongs to a banner that expired long ago and will
    /// never be returned again.
    private static let maxRemembered = 20

    /// Injectable so tests don't write into the real `UserDefaults.standard`
    /// and race the rest of the suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func dismissedIDs() -> [String] {
        defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func isDismissed(_ bannerID: String) -> Bool {
        dismissedIDs().contains(bannerID)
    }

    func markDismissed(_ bannerID: String) {
        var next = dismissedIDs().filter { $0 != bannerID }
        next.insert(bannerID, at: 0)
        if next.count > Self.maxRemembered {
            next = Array(next.prefix(Self.maxRemembered))
        }
        defaults.set(next, forKey: Self.storageKey)
    }
}
