import SwiftUI
import WellSpentAPI

/// "What's new", shown the first time a reader opens a version.
///
/// Two sections: this app, and the server behind it. They ship independently —
/// different version numbers, different days — so merging them would make it
/// impossible to tell which one changed what.
struct WhatsNewSheet: View {
    /// Captured arrays rather than the view model: the caller marks these
    /// versions seen the moment it decides to present, so reading them live
    /// would find an empty list by the time this renders.
    let appReleases: [Wellspent_V1_ChangelogRelease]
    let serverReleases: [Wellspent_V1_ChangelogRelease]
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

    private func section(title: LocalizedStringKey, releases: [Wellspent_V1_ChangelogRelease]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ReleaseNotesList(releases: releases, localeIdentifier: localeIdentifier)
        }
    }
}
