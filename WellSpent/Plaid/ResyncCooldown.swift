import Foundation
import WellSpentAPI

/// Why a connection's re-sync control is unavailable.
///
/// Mirrors web's `resyncCooldown.ts` exactly, and for the same reason: the
/// backend refuses each of these independently, so this only decides what the
/// button looks like — the user learns the reason before tapping rather than
/// from an error afterwards.
nonisolated enum ResyncCooldown {
    enum BlockedReason: Equatable {
        case notOwner
        case syncDisabled
        case cooldown
    }

    static func blockedReason(
        for connection: Wellspent_V1_PlaidConnection,
        now: Date = Date()
    ) -> BlockedReason? {
        // Ownership is checked before entitlement so a co-member is never
        // shown an upgrade prompt for someone else's plan.
        if !connection.isOwner { return .notOwner }
        if !connection.syncEnabled { return .syncDisabled }
        if connection.hasResyncAvailableAt, connection.resyncAvailableAt.date > now { return .cooldown }
        return nil
    }

    /// Whole hours until the next re-sync is allowed, rounded up and floored
    /// at 1.
    ///
    /// Rounding up matters: 90 minutes rendered as "1 hour" invites a retry
    /// that still fails. Anything under an hour reports 1 for the same reason.
    static func hoursUntilAvailable(
        for connection: Wellspent_V1_PlaidConnection,
        now: Date = Date()
    ) -> Int {
        guard connection.hasResyncAvailableAt else { return 0 }
        let seconds = connection.resyncAvailableAt.date.timeIntervalSince(now)
        if seconds <= 0 { return 0 }
        return max(1, Int(ceil(seconds / 3600)))
    }
}
