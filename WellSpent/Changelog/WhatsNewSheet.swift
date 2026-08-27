import SwiftUI
import WellSpentAPI
import WellSpentREST

/// "What's new", shown the first time a reader opens a version.
///
/// Two sections: this app, and the server behind it. They ship independently —
/// different version numbers, different days — so merging them would make it
/// impossible to tell which one changed what.
struct WhatsNewSheet: View {
    /// Captured arrays rather than the view model: the caller marks these
    /// versions seen the moment it decides to present, so reading them live
    /// would find an empty list by the time this renders.
    let appReleases: [ChangelogRelease]
    let serverReleases: [ChangelogRelease]
    let localeIdentifier: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !appReleases.isEmpty {
                        section(title: "This app", releases: appReleases)
                    }
                    if !serverReleases.isEmpty {
                        section(title: "Behind the scenes", releases: serverReleases)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .sheetChrome(Text("What's new"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { onDismiss() }
                        .accessibilityIdentifier("dismissWhatsNewButton")
                }
            }
        }
    }

    private func section(title: LocalizedStringKey, releases: [ChangelogRelease]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ReleaseNotesList(releases: releases, localeIdentifier: localeIdentifier)
        }
    }
}

#Preview {
    // Sample data, so the sheet renders in the canvas with no backend and
    // nothing published — this is the quickest way to look at the layout.
    // Both sections are populated on purpose: the divider between "This app"
    // and "Behind the scenes" only appears when both have something to say.
    func release(_ version: String, _ items: [(ChangeType, String)]) -> ChangelogRelease {
        ChangelogRelease(
            id: version,
            component: .ios,
            version: version,
            releasedAt: .now,
            items: items.map { type, summary in
                ChangelogItem(changeType: type, summaryEn: summary, summaryEs: "")
            },
            createdAt: .now
        )
    }

    return WhatsNewSheet(
        appReleases: [
            release("1.36.0", [
                (.added, "See what changed: new versions now show a short summary the first time you open them."),
                (.added, "A Help section in Settings lets you browse release notes for any past version."),
                (.changed, "Expanding a category in the Expense Overview now lists each person's transactions under their own row."),
                (.fixed, "Payment plan progress no longer counts a payment before it is due.")
            ]),
            release("1.35.3", [
                (.fixed, "Sheet titles no longer get cut off on narrow screens.")
            ])
        ],
        serverReleases: [
            release("1.0.0", [
                (.added, "Release notes are now recorded per version, so you can see what changed behind the app too.")
            ])
        ],
        localeIdentifier: "en"
    ) {}
}
