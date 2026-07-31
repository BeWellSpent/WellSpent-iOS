import WellSpentAPI

/// Display text for an `InviteStatus`.
nonisolated enum InviteStatusLabel {
    static func text(for status: Wellspent_V1_InviteStatus) -> String {
        switch status {
        case .unspecified: return "Unknown"
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        case .UNRECOGNIZED: return "Unknown"
        }
    }
}
