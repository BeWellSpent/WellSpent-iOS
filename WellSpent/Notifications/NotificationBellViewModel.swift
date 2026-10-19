import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class NotificationBellViewModel {
    private(set) var unreadCount = 0
    private(set) var notifications: [Wellspent_V1_Notification] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let restClient: WellSpentREST.Client

    init(budgetProfileID: String, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.restClient = restClient
    }

    /// Runs for the lifetime of the caller's `.task` (auto-cancelled when
    /// that view disappears) — meant to be started once from `BudgetDetailView`,
    /// not per-toolbar-appearance, so tab switches don't restart the loop.
    func pollUnreadCount() async {
        while !Task.isCancelled {
            await refreshUnreadCount()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    func refreshUnreadCount() async {
        guard let output = try? await restClient.getUnreadCount(.init()), case .ok(let ok) = output, let body = try? ok.body.json else { return }
        unreadCount = body.count
    }

    /// Lazy — only called when the popover actually opens, mirroring web's
    /// `enabled: open` query gate.
    func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let output = try await restClient.listNotifications(.init(query: .init(budgetProfileId: budgetProfileID, limit: 20)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load notifications."
                return
            }
            notifications = body.notifications.map(NotificationRESTMapping.notification(from:))
            unreadCount = body.unreadCount
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load notifications."
        }
    }

    func markAllRead() async {
        guard case .ok = try? await restClient.markNotificationsRead(.init(body: .json(.init()))) else { return }
        notifications = notifications.map { notification in
            var updated = notification
            updated.isRead = true
            return updated
        }
        unreadCount = 0
    }
}
