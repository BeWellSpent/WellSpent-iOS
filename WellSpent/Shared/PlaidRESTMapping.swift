import Foundation
import WellSpentAPI
import WellSpentREST

/// Converts the Plaid-domain REST schemas into the same proto messages every call site already consumes.
nonisolated enum PlaidRESTMapping {
    static func connection(from c: Components.Schemas.PlaidConnection) -> Wellspent_V1_PlaidConnection {
        .with {
            $0.id = c.id
            $0.institutionID = c.institutionId
            $0.institutionName = c.institutionName
            $0.status = c.status.rawValue
            if let lastSyncedAt = c.lastSyncedAt {
                $0.lastSyncedAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: lastSyncedAt)
            }
            $0.budgetProfileID = c.budgetProfileId
            $0.ownerName = c.ownerName
            $0.isOwner = c.isOwner
            $0.syncEnabled = c.syncEnabled
            if let resyncAvailableAt = c.resyncAvailableAt {
                $0.resyncAvailableAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: resyncAvailableAt)
            }
        }
    }

    static func syncWarning(from w: Components.Schemas.BudgetSyncWarning) -> Wellspent_V1_BudgetSyncWarning {
        .with {
            $0.budgetProfileID = w.budgetProfileId
            $0.budgetName = w.budgetName
            $0.memberName = w.memberName
            $0.connectionCount = Int32(w.connectionCount)
            $0.isCurrentUser = w.isCurrentUser
        }
    }
}
