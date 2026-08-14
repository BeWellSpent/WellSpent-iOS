import SwiftUI
import WellSpentAPI

struct PlaidConnectionRow: View {
    let connection: Wellspent_V1_PlaidConnection
    /// Which budget this feeds (Settings) or who linked it (a budget's manage
    /// view) — the only thing that differs between the two screens.
    let subtitle: String
    let isManagingAccounts: Bool
    let isDisconnecting: Bool
    let isResyncing: Bool
    var manageAccountsDisabled: Bool = false
    let onManageAccounts: () -> Void
    let onDisconnect: () -> Void
    let onResync: () -> Void

    /// Not `static` — must be rebuilt with the current locale on every
    /// access so a language change (which can happen without relaunching
    /// the app) is reflected immediately, rather than caching the locale
    /// that was active the first time this row was ever rendered.
    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = AppLanguageStore.currentLocale
        return formatter
    }

    private var isConnected: Bool { connection.status != "disconnected" }
    private var isBusy: Bool { isManagingAccounts || isDisconnecting || isResyncing }
    private var resyncBlocked: ResyncCooldown.BlockedReason? {
        ResyncCooldown.blockedReason(for: connection)
    }

    private var lastSyncedText: String {
        guard connection.hasLastSyncedAt else {
            return String(localized: "Never synced", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
        let relative = relativeFormatter.localizedString(for: connection.lastSyncedAt.date, relativeTo: Date())
        return String(localized: "Synced \(relative)", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    (connection.institutionName.isEmpty ? Text("Unknown bank") : Text(connection.institutionName))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(PlaidStatusLabel.text(for: connection.status))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(PlaidStatusColor.color(for: connection.status).opacity(0.2))
                        .foregroundStyle(PlaidStatusColor.color(for: connection.status))
                        .clipShape(Capsule())

                    // A connection whose owner isn't on a paid plan is a
                    // healthy link that imports nothing, so the status chip
                    // on its own reads as fine.
                    if isConnected && !connection.syncEnabled {
                        Text("Not syncing")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                Text("\(subtitle) · \(lastSyncedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                HStack(spacing: 12) {
                    Button {
                        onResync()
                    } label: {
                        if isResyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || resyncBlocked != nil)
                    .accessibilityIdentifier("resyncConnection_\(connection.id)")

                    Button {
                        onManageAccounts()
                    } label: {
                        if isManagingAccounts {
                            ProgressView()
                        } else {
                            Image(systemName: "gearshape")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || manageAccountsDisabled || !connection.isOwner)
                    .accessibilityIdentifier("manageAccounts_\(connection.id)")

                    Button {
                        onDisconnect()
                    } label: {
                        if isDisconnecting {
                            ProgressView()
                        } else {
                            Image(systemName: "link.badge.minus")
                                .foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || !connection.isOwner)
                    .accessibilityIdentifier("disconnectConnection_\(connection.id)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("plaidConnectionRow_\(connection.institutionName)")
    }
}

#Preview {
    List {
        PlaidConnectionRow(
            connection: .with {
                $0.id = "conn-1"
                $0.institutionName = "Chase"
                $0.status = "active"
                $0.budgetProfileID = "budget-1"
                $0.isOwner = true
                $0.syncEnabled = true
            },
            subtitle: "Household Budget",
            isManagingAccounts: false,
            isDisconnecting: false,
            isResyncing: false,
            onManageAccounts: {},
            onDisconnect: {},
            onResync: {}
        )
    }
}
