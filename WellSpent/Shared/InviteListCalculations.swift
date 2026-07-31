import WellSpentAPI

/// Pure invite-list derivation, mirroring web's `InvitePanel.tsx` `useMemo`.
nonisolated enum InviteListCalculations {
    /// Resends create new invite rows rather than mutating the old one, so
    /// the same email can have several rows over time — only the one with
    /// the latest `expiresAt` should be shown.
    static func latestPerEmail(_ invites: [Wellspent_V1_BudgetInvite]) -> [Wellspent_V1_BudgetInvite] {
        var byEmail: [String: Wellspent_V1_BudgetInvite] = [:]
        for invite in invites {
            if let existing = byEmail[invite.email] {
                if invite.expiresAt.date > existing.expiresAt.date {
                    byEmail[invite.email] = invite
                }
            } else {
                byEmail[invite.email] = invite
            }
        }
        return Array(byEmail.values)
    }
}
