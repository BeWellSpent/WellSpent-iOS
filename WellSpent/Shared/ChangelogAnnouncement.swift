import Foundation
import WellSpentAPI
import WellSpentREST

/// Which releases to put in front of the reader, for one component.
///
/// Mirrors web's `components/changelog/announce.ts` deliberately — the two are
/// named so the pairing is obvious, and a change to one belongs in the other.
nonisolated enum ChangelogAnnouncement {
    /// `releases` must be that component's own, newest first — the order the
    /// server returns them in.
    ///
    /// Three rules, each earning its place:
    ///
    /// 1. **Nothing newer than what is actually running.** A backend deploy can
    ///    publish notes before a build reaches TestFlight, and announcing a
    ///    version the reader does not have is worse than announcing nothing.
    ///    For the server component `currentVersion` is what the API reports
    ///    about itself, so the same rule holds there.
    /// 2. **A first-ever run announces nothing.** Someone opening the app for
    ///    the first time should not meet the entire history of the product;
    ///    their version is simply recorded. Help is where history lives.
    /// 3. **Everything between what they last saw and now**, so a reader who
    ///    skips three releases still learns what changed in all three.
    ///
    /// A `lastSeenVersion` absent from the list — notes removed, or history
    /// truncated by the per-component limit — falls back to the newest single
    /// release rather than replaying everything.
    static func releasesToAnnounce(
        _ releases: [ChangelogRelease],
        currentVersion: String,
        lastSeenVersion: String?
    ) -> [ChangelogRelease] {
        // No notes published for the running version yet: everything here is
        // either older (fine) or not-yet-shipped-to-this-client
        // (indistinguishable from here), so fall through and let the
        // last-seen rules below do the trimming.
        let visible: [ChangelogRelease]
        if let currentIndex = releases.firstIndex(where: { $0.version == currentVersion }) {
            visible = Array(releases[currentIndex...])
        } else {
            visible = releases
        }

        guard let lastSeenVersion else { return [] }

        guard let seenIndex = visible.firstIndex(where: { $0.version == lastSeenVersion }) else {
            return Array(visible.prefix(1))
        }
        return Array(visible[..<seenIndex])
    }

    /// The reader's language, falling back to English when there is no
    /// translation — `summary_es` is optional on the row.
    static func localizedSummary(_ item: ChangelogItem, localeIdentifier: String) -> String {
        if localeIdentifier.hasPrefix("es"), !item.summaryEs.trimmingCharacters(in: .whitespaces).isEmpty {
            return item.summaryEs
        }
        return item.summaryEn
    }
}
