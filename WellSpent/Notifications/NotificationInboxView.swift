import SwiftUI
import WellSpentAPI

struct NotificationInboxView: View {
    let viewModel: NotificationBellViewModel?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel?.isLoading == true && (viewModel?.notifications.isEmpty ?? true) {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (viewModel?.notifications ?? []).isEmpty {
                Text("No notifications yet.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(viewModel?.notifications ?? [], id: \.id) { notification in
                    row(notification)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 340, height: 420)
        .task {
            await viewModel?.loadNotifications()
        }
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)
            Spacer()
            if (viewModel?.unreadCount ?? 0) > 0 {
                Button("Mark all read") {
                    Task { await viewModel?.markAllRead() }
                }
                .font(.subheadline)
                .accessibilityIdentifier("markAllReadButton")
            }
        }
        .padding()
    }

    private func row(_ notification: Wellspent_V1_Notification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notification.title)
                .font(.subheadline)
                .fontWeight(notification.isRead ? .regular : .semibold)
            if !notification.body.isEmpty {
                Text(notification.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if notification.hasCreatedAt {
                Text(Self.relativeFormatter.localizedString(for: notification.createdAt.date, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(notification.isRead ? Color.clear : Color.accentColor.opacity(0.08))
    }
}

#Preview {
    NotificationInboxView(viewModel: nil)
}
