import Foundation
import WellSpentAPI

/// The backend transmits DATE-only fields (`transaction.date`, `budget_period`
/// start/end, `fixed_expense.anchor_date`/`end_date`, `paid_date`, ...) as
/// proto Timestamps at midnight UTC — confirmed via
/// `WellSpent-backend/internal/handler/convert.go`'s `protoTSFromDate`
/// ("converts pgtype.Date to proto Timestamp (midnight UTC)"). Formatting,
/// grouping, or comparing these with the device's local timezone shifts the
/// displayed day backward for any timezone behind UTC (i.e. the whole
/// Americas) — e.g. midnight UTC on Aug 1 is 5pm on Jul 31 in Pacific time.
/// These two functions convert between that UTC-midnight wire
/// representation and a local `Date` that actually represents the same
/// calendar day once formatted/grouped locally. Real timestamps with
/// genuine time-of-day meaning (e.g. `budget_invite.expires_at`,
/// `notification.created_at`) are NOT DATE-only fields and must not go
/// through these. Prefer `Google_Protobuf_Timestamp.dateOnly` /
/// `Google_Protobuf_Timestamp(dateOnly:)` below at call sites — these two
/// functions are the underlying pure logic, kept separate so they're
/// directly unit-testable without constructing a Timestamp.
nonisolated enum DateOnly {
    /// A Timestamp-derived `Date` (midnight UTC, as sent by the backend) ->
    /// a local `Date` representing midnight of that same calendar day, so
    /// any local `Calendar`/`DateFormatter` call downstream shows the
    /// correct day.
    static func local(fromUTCMidnight date: Date) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        return localCalendar.date(from: components) ?? date
    }

    /// A locally-picked calendar day (e.g. from a `DatePicker`) -> midnight
    /// UTC of that same calendar day, matching the backend's wire
    /// convention for DATE-only fields.
    static func utcMidnight(fromLocal date: Date) -> Date {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.date(from: components) ?? date
    }
}

extension Google_Protobuf_Timestamp {
    /// This timestamp, correctly reinterpreted as a DATE-only field's local
    /// calendar day — use this (not `.date`) whenever reading a field
    /// documented as DATE-only. e.g. `transaction.date.dateOnly`,
    /// `period.startDate.dateOnly`, `expense.anchorDate.dateOnly`.
    var dateOnly: Date {
        DateOnly.local(fromUTCMidnight: date)
    }

    /// Builds a DATE-only field's wire representation (midnight UTC) from a
    /// locally-picked calendar day — use this (not `Timestamp(date:)`)
    /// whenever writing a field documented as DATE-only. e.g.
    /// `$0.date = Google_Protobuf_Timestamp(dateOnly: pickedDate)`.
    init(dateOnly localDate: Date) {
        self.init(date: DateOnly.utcMidnight(fromLocal: localDate))
    }
}
