import SwiftUI
import WellSpentAPI

struct PlaidConnectionRow: View {
    let connection: Wellspent_V1_PlaidConnection
    let budgetName: String
    let isManagingAccounts: Bool
    let isDisconnecting: Bool
    let onManageAccounts: () -> Void
    let onDisconnect: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var isConnected: Bool { connection.status != "disconnected" }

    private var lastSyncedText: String {
        guard connection.hasLastSyncedAt else { return "Never synced" }
        return "Synced " + Self.relativeFormatter.localizedString(for: connection.lastSyncedAt.date, relativeTo: Date())
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(connection.institutionName.isEmpty ? "Unknown bank" : connection.institutionName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(connection.status)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(PlaidStatusColor.color(for: connection.status).opacity(0.2))
                        .foregroundStyle(PlaidStatusColor.color(for: connection.status))
                        .clipShape(Capsule())
                }
                Text("\(budgetName) · \(lastSyncedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                HStack(spacing: 12) {
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
                    .disabled(isManagingAccounts || isDisconnecting)
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
                    .disabled(isManagingAccounts || isDisconnecting)
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
            },
            budgetName: "Household Budget",
            isManagingAccounts: false,
            isDisconnecting: false,
            onManageAccounts: {},
            onDisconnect: {}
        )
    }
}
