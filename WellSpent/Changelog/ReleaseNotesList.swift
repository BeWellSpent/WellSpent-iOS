import SwiftUI
import WellSpentAPI
import WellSpentREST

/// A list of releases with their items. Shared by the what's-new sheet and the
/// Help browser so the two cannot drift into rendering the same notes
/// differently.
///
/// Items keep the order the operator wrote them in rather than being grouped by
/// type: a release usually reads as a short narrative, and re-sorting it into
/// buckets breaks that for tidiness nobody asked for.
struct ReleaseNotesList: View {
    let releases: [ChangelogRelease]
    let localeIdentifier: String

    var body: some View {
        if releases.isEmpty {
            Text("No release notes yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(releases, id: \.id) { release in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: release.version)
                                .font(.subheadline.weight(.bold))
                            // `releasedAt` is required by the contract, so
                            // there is no "unset" case to guard any more — the
                            // proto version needed `hasReleasedAt` because
                            // every message field is optional on the wire.
                            do {
                                Text(release.releasedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(verbatim: Self.label(for: item.changeType))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Self.tint(for: item.changeType).opacity(0.15))
                                    .foregroundStyle(Self.tint(for: item.changeType))
                                    .clipShape(Capsule())
                                Text(verbatim: ChangelogAnnouncement.localizedSummary(item, localeIdentifier: localeIdentifier))
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityIdentifier("changelogRelease_\(release.version)")
                }
            }
        }
    }

    /// Namespaced keys rather than the English words themselves.
    ///
    /// `"Fixed"` is already a catalog key in this app meaning a *fixed
    /// expense* — Spanish "Fijo". Reusing it here would put "Fijo" on a
    /// bug-fix chip. Identity and display are different jobs; a literal doing
    /// both collides the moment two features want the same word.
    private static func label(for type: ChangeType) -> String {
        switch type {
        case .added:
            return String(localized: "changelog.type.added", defaultValue: "Added",
                          bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .fixed:
            return String(localized: "changelog.type.fixed", defaultValue: "Fixed",
                          bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        default:
            // An unrecognised type reads as "Changed" rather than blank — a
            // value added to the enum after this build shipped still renders.
            return String(localized: "changelog.type.changed", defaultValue: "Changed",
                          bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
    }

    /// Semantic colours, independent of the app accent — an unrecognised type
    /// renders as "changed" rather than falling through to nothing.
    private static func tint(for type: ChangeType) -> Color {
        switch type {
        case .added: return .green
        case .fixed: return .orange
        default: return .blue
        }
    }
}

#Preview {
    ReleaseNotesList(
        releases: [
            ChangelogRelease(
                id: "r1",
                component: .ios,
                version: "1.36.0",
                releasedAt: .now,
                items: [
                    ChangelogItem(changeType: .added, summaryEn: "Release notes now appear when you open a new version.", summaryEs: ""),
                    ChangelogItem(changeType: .fixed, summaryEn: "Payment progress no longer counts a bill before it is due.", summaryEs: "")
                ],
                createdAt: .now
            )
        ],
        localeIdentifier: "en"
    )
    .padding()
}
