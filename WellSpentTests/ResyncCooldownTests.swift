import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ResyncCooldown")
struct ResyncCooldownTests {
    private static let now = Date(timeIntervalSince1970: 1_786_622_400) // 2026-08-13T12:00:00Z

    private func connection(
        isOwner: Bool = true,
        syncEnabled: Bool = true,
        availableAt: Date? = nil
    ) -> Wellspent_V1_PlaidConnection {
        .with {
            $0.id = "conn-1"
            $0.isOwner = isOwner
            $0.syncEnabled = syncEnabled
            if let availableAt {
                $0.resyncAvailableAt = Google_Protobuf_Timestamp(date: availableAt)
            }
        }
    }

    @Test("An owned, entitled connection with no recorded resync is available")
    func availableByDefault() {
        #expect(ResyncCooldown.blockedReason(for: connection(), now: Self.now) == nil)
    }

    @Test("A connection the caller doesn't own is blocked")
    func blockedForNonOwner() {
        #expect(ResyncCooldown.blockedReason(for: connection(isOwner: false), now: Self.now) == .notOwner)
    }

    @Test("A connection whose owner isn't entitled to sync is blocked")
    func blockedWhenSyncDisabled() {
        // Clearing the cursor here would discard the owner's place in the feed
        // and import nothing, since the sync job skips them on every run.
        #expect(ResyncCooldown.blockedReason(for: connection(syncEnabled: false), now: Self.now) == .syncDisabled)
    }

    @Test("Ownership is reported before entitlement, so a co-member never sees an upgrade prompt")
    func ownershipTakesPrecedence() {
        let conn = connection(isOwner: false, syncEnabled: false)
        #expect(ResyncCooldown.blockedReason(for: conn, now: Self.now) == .notOwner)
    }

    @Test("A cooldown still in the future blocks")
    func blockedDuringCooldown() {
        let conn = connection(availableAt: Self.now.addingTimeInterval(6 * 3600))
        #expect(ResyncCooldown.blockedReason(for: conn, now: Self.now) == .cooldown)
    }

    @Test("A cooldown that has passed no longer blocks")
    func availableAfterCooldown() {
        let conn = connection(availableAt: Self.now.addingTimeInterval(-60))
        #expect(ResyncCooldown.blockedReason(for: conn, now: Self.now) == nil)
    }

    @Test("Remaining hours round up, so a partial hour never reads as fewer than it is")
    func hoursRoundUp() {
        // 90 minutes shown as "1 hour" would invite a retry that still fails.
        let conn = connection(availableAt: Self.now.addingTimeInterval(90 * 60))
        #expect(ResyncCooldown.hoursUntilAvailable(for: conn, now: Self.now) == 2)
    }

    @Test("Remaining hours floor at 1 rather than reading 0 while still blocked")
    func hoursFloorAtOne() {
        let conn = connection(availableAt: Self.now.addingTimeInterval(60))
        #expect(ResyncCooldown.hoursUntilAvailable(for: conn, now: Self.now) == 1)
    }

    @Test("Remaining hours are 0 once the time has passed")
    func hoursZeroWhenElapsed() {
        let conn = connection(availableAt: Self.now.addingTimeInterval(-3600))
        #expect(ResyncCooldown.hoursUntilAvailable(for: conn, now: Self.now) == 0)
    }

    @Test("Remaining hours are 0 when no cooldown is recorded")
    func hoursZeroWhenUnset() {
        #expect(ResyncCooldown.hoursUntilAvailable(for: connection(), now: Self.now) == 0)
    }
}
