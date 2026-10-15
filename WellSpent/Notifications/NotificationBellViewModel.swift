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

    private let client: Wellspent_V1_NotificationServiceClient
    private let restClient: WellSpentREST.Client

    init(budgetProfileID: String, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.client = Wellspent_V1_NotificationServiceClient(client: authenticatedClient)
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
        if FeatureFlags.csharpNotificationEnabled {
            guard let output = try? await restClient.getUnreadCount(.init()), case .ok(let ok) = output, let body = try? ok.body.json else { return }
            unreadCount = body.count
            return
        }
        let response = await client.getUnreadCount(request: Wellspent_V1_GetUnreadCountRequest())
        if case .success(let message) = response.result {
            unreadCount = Int(message.count)
        }
    }

    /// Lazy — only called when the popover actually opens, mirroring web's
    /// `enabled: open` query gate.
    func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if FeatureFlags.csharpNotificationEnabled {
            await loadNotificationsViaREST()
            return
        }

        let response = await client.listNotifications(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.limit = 20
        })

        switch response.result {
        case .success(let message):
            notifications = message.notifications
            unreadCount = Int(message.unreadCount)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load notifications."
        }
    }

    private func loadNotificationsViaREST() async {
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
        if FeatureFlags.csharpNotificationEnabled {
            guard case .ok = try? await restClient.markNotificationsRead(.init(body: .json(.init()))) else { return }
        } else {
            guard case .success = await client.markNotificationsRead(request: Wellspent_V1_MarkNotificationsReadRequest()).result else { return }
        }
        notifications = notifications.map { notification in
            var updated = notification
            updated.isRead = true
            return updated
        }
        unreadCount = 0
    }
}
