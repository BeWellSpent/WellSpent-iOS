import Foundation

/// Remembers which versions the reader has already been shown notes for.
///
/// On-device on purpose, matching web and the same call as
/// `StatusBannerDismissalStore`: "the first time this version is opened" is
/// inherently per-install — the app on this phone has its own version — so a
/// per-user column would be the wrong shape and would need a write on every
/// launch. The trade-off is that installing on a second device shows the notes
/// again there.
nonisolated struct ChangelogSeenStore {
    private let defaults: UserDefaults
    private static let storageKey = "changelogSeenVersions"

    /// Injectable so tests don't write into the real `UserDefaults.standard`
    /// and race the rest of the suite — the same hazard that has bitten
    /// `AppLanguageStore` three times.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Last announced version per component, or `nil` for a component never
    /// seen — which is what marks a first-ever run.
    func lastSeen(component: ChangelogComponentKey) -> String? {
        stored()[component.rawValue]
    }

    func markSeen(component: ChangelogComponentKey, version: String) {
        var next = stored()
        next[component.rawValue] = version
        defaults.set(next, forKey: Self.storageKey)
    }

    private func stored() -> [String: String] {
        // Anything else under this key is a corrupted write; treat it as empty
        // rather than trapping on every launch forever.
        defaults.dictionary(forKey: Self.storageKey)?.compactMapValues { $0 as? String } ?? [:]
    }
}

/// The components this client tracks a seen-version for. iOS never announces
/// web's releases, so only its own and the server's are here — the Help
/// browser shows all three, but browsing is not announcing.
nonisolated enum ChangelogComponentKey: String {
    case ios
    case server
}
