import Foundation
import WellSpentAPI
import WellSpentREST

/// Converts the Invite-domain REST schemas into the same proto messages every call site already consumes.
nonisolated enum InviteRESTMapping {
    static func invite(from i: Components.Schemas.BudgetInvite) -> Wellspent_V1_BudgetInvite {
        .with {
            $0.id = i.id
            $0.budgetProfileID = i.budgetProfileId
            $0.budgetName = i.budgetName
            $0.inviterName = i.inviterName
            $0.email = i.email
            $0.role = role(from: i.role)
            $0.status = status(from: i.status)
            $0.expiresAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: i.expiresAt)
            $0.createdAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: i.createdAt)
            $0.budgetPersonID = i.budgetPersonId ?? 0
        }
    }

    static func role(from r: Components.Schemas.BudgetInviteRole) -> Wellspent_V1_BudgetRole {
        switch r {
        case .admin: return .admin
        case .collaborator: return .collaborator
        case .viewer: return .viewer
        }
    }

    static func status(from s: Components.Schemas.InviteStatus) -> Wellspent_V1_InviteStatus {
        switch s {
        case .pending: return .pending
        case .accepted: return .accepted
        case .cancelled: return .cancelled
        case .expired: return .expired
        }
    }

    /// `sendBudgetInvite`/`resend` only ever send collaborator/viewer — admin is UI-unreachable.
    static func sendRole(from r: Wellspent_V1_BudgetRole) -> Components.Schemas.SendBudgetInviteRequest.rolePayload {
        r == .viewer ? .viewer : .collaborator
    }
}
