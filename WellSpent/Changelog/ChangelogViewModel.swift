import Foundation
import Observation
import os
import WellSpentREST

/// Loads release notes for the "what's new" prompt and the Help browser.
///
/// One view model serves both: they read the same data, and the Help browser
/// wants every component while the prompt wants this client's plus the
/// server's — a difference in filtering, not in fetching.
@MainActor
@Observable
final class ChangelogViewModel {
    private static let logger = AppLogger.logger("Changelog")

    private(set) var isLoading = false
    private(set) var releases: [ChangelogRelease] = []
    /// What the API reports about itself. A client cannot otherwise tell which
    /// server releases are new to it.
    private(set) var serverVersion = ""
    private(set) var errorMessage: String?

    private let client: WellSpentREST.Client
    private let seenStore: ChangelogSeenStore

    init(authenticatedClient: WellSpentREST.Client, seenStore: ChangelogSeenStore = ChangelogSeenStore()) {
        self.client = authenticatedClient
        self.seenStore = seenStore
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Every component: the Help browser shows all three, and the prompt
        // filters down from the same response rather than fetching twice.
        do {
            let response = try await client.changelog()
            releases = response.releases
            serverVersion = response.currentServerVersion
            Self.logger.info("loaded changelog releases=\(response.releases.count, privacy: .public) serverVersion=\(response.currentServerVersion, privacy: .public)")
        } catch {
            // Release notes are not worth an error banner over — a reader who
            // cannot see them has lost nothing they were doing.
            errorMessage = error.localizedDescription
            Self.logger.error("failed to load changelog error=\(String(describing: error), privacy: .public)")
        }
    }

    func releases(for component: ChangelogComponent) -> [ChangelogRelease] {
        releases.filter { $0.component == component }
    }

    /// This client's unseen releases, and the server's. Empty on a first-ever
    /// run — see `ChangelogAnnouncement`.
    var unseenAppReleases: [ChangelogRelease] {
        ChangelogAnnouncement.releasesToAnnounce(
            releases(for: .ios),
            currentVersion: AppVersion.marketingVersion ?? "",
            lastSeenVersion: seenStore.lastSeen(component: .ios)
        )
    }

    var unseenServerReleases: [ChangelogRelease] {
        ChangelogAnnouncement.releasesToAnnounce(
            releases(for: .server),
            currentVersion: serverVersion,
            lastSeenVersion: seenStore.lastSeen(component: .server)
        )
    }

    var hasSomethingToAnnounce: Bool {
        !unseenAppReleases.isEmpty || !unseenServerReleases.isEmpty
    }

    /// Records what this reader is on, whether or not anything was announced —
    /// a first-ever run has to be recorded too, or the next launch would treat
    /// it as first-ever again and never announce anything.
    func markCurrentVersionsSeen() {
        if let marketingVersion = AppVersion.marketingVersion {
            seenStore.markSeen(component: .ios, version: marketingVersion)
        }
        if !serverVersion.isEmpty {
            seenStore.markSeen(component: .server, version: serverVersion)
        }
    }

    /// Test seam, matching `AlertsViewModel`'s.
    func setStateForTesting(releases: [ChangelogRelease], serverVersion: String) {
        self.releases = releases
        self.serverVersion = serverVersion
    }
}
