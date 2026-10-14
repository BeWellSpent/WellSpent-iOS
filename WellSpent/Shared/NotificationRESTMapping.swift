import Foundation
import WellSpentAPI
import WellSpentREST

/// Converts the Notification-domain REST schemas into the same proto messages every call site already consumes.
nonisolated enum NotificationRESTMapping {
    static func notification(from n: Components.Schemas.Notification) -> Wellspent_V1_Notification {
        .with {
            $0.id = n.id
            $0.userID = n.userId
            $0.budgetProfileID = n.budgetProfileId ?? ""
            $0.alertType = n.alertType
            $0.title = n.title
            $0.body = n.body ?? ""
            $0.isRead = n.isRead
            $0.createdAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: n.createdAt)
        }
    }

    static func alertSubscription(from s: Components.Schemas.AlertSubscription) -> Wellspent_V1_AlertSubscription {
        .with {
            $0.id = s.id
            $0.userID = s.userId
            $0.budgetProfileID = s.budgetProfileId
            $0.alertType = s.alertType
            $0.channel = s.channel
            $0.thresholdPct = Float(s.thresholdPct ?? 0)
            $0.thresholdScope = s.thresholdScope ?? ""
            $0.categoryID = Int32(s.categoryId ?? 0)
            $0.notifyAllMembers = s.notifyAllMembers
        }
    }
}
