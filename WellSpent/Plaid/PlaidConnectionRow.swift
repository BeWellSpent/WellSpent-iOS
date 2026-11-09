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
    let isSyncing: Bool
    var manageAccountsDisabled: Bool = false
    let onManageAccounts: () -> Void
    let onDisconnect: () -> Void
    let onResync: () -> Void
    let onSync: () -> Void

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
    private var isBusy: Bool { isManagingAccounts || isDisconnecting || isResyncing || isSyncing }
    private var syncBlocked: ResyncCooldown.BlockedReason? {
        ResyncCooldown.syncBlockedReason(for: connection)
    }
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
                if isBusy {
                    ProgressView()
                } else {
                    Menu {
                        Button {
                            onSync()
                        } label: {
                            Label("Sync now", systemImage: "arrow.clockwise")
                        }
                        .disabled(syncBlocked != nil)
                        .accessibilityIdentifier("syncConnection_\(connection.id)")

                        Button {
                            onResync()
                        } label: {
                            Label("Re-sync from scratch", systemImage: "clock.arrow.circlepath")
                        }
                        .disabled(resyncBlocked != nil)
                        .accessibilityIdentifier("resyncConnection_\(connection.id)")

                        Divider()

                        Button {
                            onManageAccounts()
                        } label: {
                            Label("Manage accounts", systemImage: "gearshape")
                        }
                        .disabled(manageAccountsDisabled || !connection.isOwner)
                        .accessibilityIdentifier("manageAccounts_\(connection.id)")

                        Button(role: .destructive) {
                            onDisconnect()
                        } label: {
                            Label("Disconnect", systemImage: "link.badge.minus")
                        }
                        .disabled(!connection.isOwner)
                        .accessibilityIdentifier("disconnectConnection_\(connection.id)")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Connection actions")
                    .accessibilityIdentifier("connectionActions_\(connection.id)")
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
            isSyncing: false,
            onManageAccounts: {},
            onDisconnect: {},
            onResync: {},
            onSync: {}
        )
    }
}
