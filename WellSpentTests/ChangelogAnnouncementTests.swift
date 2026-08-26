import Foundation
import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("ChangelogAnnouncement")
struct ChangelogAnnouncementTests {
    private func release(_ version: String) -> ChangelogRelease {
        ChangelogRelease(
            id: version,
            component: .ios,
            version: version,
            releasedAt: .now,
            items: [],
            createdAt: .now
        )
    }

    /// Newest first, the order the server returns them in.
    private var history: [ChangelogRelease] {
        [release("1.3.0"), release("1.2.0"), release("1.1.0"), release("1.0.0")]
    }

    // Someone opening the app for the first time should not meet the entire
    // history of the product.
    @Test("a first-ever run announces nothing")
    func firstRunIsQuiet() {
        let out = ChangelogAnnouncement.releasesToAnnounce(history, currentVersion: "1.3.0", lastSeenVersion: nil)
        #expect(out.isEmpty)
    }

    @Test("announces every release since the one last seen, not just the newest")
    func announcesEverythingMissed() {
        let out = ChangelogAnnouncement.releasesToAnnounce(history, currentVersion: "1.3.0", lastSeenVersion: "1.1.0")
        #expect(out.map(\.version) == ["1.3.0", "1.2.0"])
    }

    @Test("announces nothing when the reader is already up to date")
    func upToDateIsQuiet() {
        let out = ChangelogAnnouncement.releasesToAnnounce(history, currentVersion: "1.3.0", lastSeenVersion: "1.3.0")
        #expect(out.isEmpty)
    }

    // A backend deploy can publish notes before a build reaches TestFlight.
    // Announcing a version the reader does not have is worse than nothing.
    @Test("never announces a version newer than the one actually running")
    func neverAnnouncesAheadOfTheBuild() {
        let out = ChangelogAnnouncement.releasesToAnnounce(history, currentVersion: "1.1.0", lastSeenVersion: "1.0.0")
        #expect(out.map(\.version) == ["1.1.0"])
    }

    @Test("falls back to the newest single release when the last seen version is gone")
    func unknownLastSeenShowsOnlyTheNewest() {
        let out = ChangelogAnnouncement.releasesToAnnounce(history, currentVersion: "1.3.0", lastSeenVersion: "0.9.0")
        #expect(out.map(\.version) == ["1.3.0"])
    }

    @Test("announces nothing when nothing has been published")
    func emptyHistoryIsQuiet() {
        let out = ChangelogAnnouncement.releasesToAnnounce([], currentVersion: "1.0.0", lastSeenVersion: "0.9.0")
        #expect(out.isEmpty)
    }

    @Test("a Spanish reader gets the Spanish summary")
    func localizedSummaryPrefersSpanish() {
        let item = ChangelogItem(changeType: .added, summaryEn: "Added a thing", summaryEs: "Agregamos algo")
        #expect(ChangelogAnnouncement.localizedSummary(item, localeIdentifier: "es") == "Agregamos algo")
        #expect(ChangelogAnnouncement.localizedSummary(item, localeIdentifier: "en") == "Added a thing")
    }

    // Spanish is optional on the row — an untranslated note must still read,
    // rather than rendering blank.
    @Test("falls back to English when there is no translation")
    func localizedSummaryFallsBack() {
        let blank = ChangelogItem(changeType: .added, summaryEn: "Added a thing", summaryEs: "")
        let spaces = ChangelogItem(changeType: .added, summaryEn: "Added a thing", summaryEs: "   ")
        #expect(ChangelogAnnouncement.localizedSummary(blank, localeIdentifier: "es") == "Added a thing")
        #expect(ChangelogAnnouncement.localizedSummary(spaces, localeIdentifier: "es") == "Added a thing")
    }
}

@Suite("ChangelogSeenStore")
struct ChangelogSeenStoreTests {
    /// Its own suite name, so this never writes into UserDefaults.standard and
    /// races the rest of the suite — the hazard that has bitten
    /// AppLanguageStore three times.
    private func store() -> (ChangelogSeenStore, UserDefaults) {
        let name = "ChangelogSeenStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ChangelogSeenStore(defaults: defaults), defaults)
    }

    @Test("remembers a version per component independently")
    func perComponent() {
        let (subject, _) = store()
        subject.markSeen(component: .ios, version: "1.36.0")
        subject.markSeen(component: .server, version: "1.0.0")
        #expect(subject.lastSeen(component: .ios) == "1.36.0")
        #expect(subject.lastSeen(component: .server) == "1.0.0")
    }

    @Test("reports nil for a component never seen, which is what marks a first run")
    func neverSeen() {
        let (subject, _) = store()
        #expect(subject.lastSeen(component: .ios) == nil)
    }

    @Test("overwrites rather than accumulating")
    func overwrites() {
        let (subject, _) = store()
        subject.markSeen(component: .ios, version: "1.36.0")
        subject.markSeen(component: .ios, version: "1.37.0")
        #expect(subject.lastSeen(component: .ios) == "1.37.0")
    }

    // A corrupted key must not trap on every launch forever.
    @Test("treats unreadable storage as empty")
    func corruptedStorage() {
        let (subject, defaults) = store()
        defaults.set(["ios": 42], forKey: "changelogSeenVersions")
        #expect(subject.lastSeen(component: .ios) == nil)
    }
}
